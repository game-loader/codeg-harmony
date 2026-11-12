import { common, Want, wantConstant } from '@kit.AbilityKit'
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit'
import { webview } from '@kit.ArkWeb'
import { app } from '../store/AppState'
import { DirEntry, FolderDetail } from '../model/Models'
import { ApiError, errorText } from '../net/ApiError'
import { copyFileInto, downloadWorkspaceFile, downloadsDir, pruneDownloads } from '../net/Downloads'
import { mimeFor } from '../session/Attachments'
import { localFileUrl } from '../session/FileRefs'
import { L, formatBytes } from '../common/I18n'
import { EmptyState, IconButton, Loading, sym, toast } from '../components/Common'
import { CodeBlock, MarkdownView, copyText } from '../components/Markdown'
import { fileIconFor } from '../components/MarkdownParse'

const IMAGE_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic']
// The types the server streams for playback.
const VIDEO_EXT = ['mp4', 'm4v', 'mov', 'webm', 'ogv', 'ogg', 'mkv', 'avi', 'mpeg', 'mpg', '3gp', '3g2']
// Known binary types: offered for saving instead of asking the server for text.
const BINARY_EXT = ['zip', 'gz', 'tgz', 'tar', 'bz2', 'xz', '7z', 'rar', 'hap', 'app', 'apk', 'ipa', 'dmg',
  'exe', 'bin', 'so', 'dylib', 'dll', 'jar', 'class', 'o', 'a', 'wasm', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
  'mp3', 'wav', 'flac', 'm4a', 'aac', 'ttf', 'otf', 'woff', 'woff2', 'ico', 'psd', 'sqlite', 'db', 'pyc', 'iso']
const MAX_IMAGE = 15000000
// A Text holding megabytes blocks the UI thread; longer files are shown in part.
const MAX_TEXT = 400000

/** A folder for one server file's local copy, so equal names from different folders stay apart. */
function cacheFolder(base: string, serverPath: string): string {
  let h = 0
  for (let i = 0; i < serverPath.length; i++) {
    h = (h * 31 + serverPath.charCodeAt(i)) | 0
  }
  const dir = `${base}/${(h >>> 0).toString(16)}`
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir)
  }
  return dir
}

export function extOf(p: string): string {
  return (p.split('.').pop() ?? '').toLowerCase()
}

export function relPath(root: string, abs: string): string {
  const r = root.endsWith('/') ? root : root + '/'
  return abs.startsWith(r) ? abs.substring(r.length) : abs.replace(new RegExp('^/+'), '')
}

/**
 * Shows one file from the server: text, Markdown, image, video or PDF inline,
 * and any file can be saved to the device or handed to another app.
 */
@ComponentV2
export struct FilePreview {
  @Param root: string = ''
  @Param path: string = ''
  /** Line the reference pointed at; 0 when none. */
  @Param lineNo: number = 0
  @Event onClose: () => void = () => {
  }
  @Local loading: boolean = true
  /** text | image | video | pdf | file (no inline preview; save or open elsewhere) */
  @Local kind: string = ''
  /** `file://` address of the downloaded copy the PDF viewer shows. */
  @Local pdfSrc: string = ''
  @Local text: string = ''
  @Local truncated: boolean = false
  @Local imageData: string = ''
  @Local videoUrl: string = ''
  /** Why there is no inline preview (kind `file`). */
  @Local note: string = ''
  @Local error: string = ''
  @Local rendered: boolean = true
  /** '' | downloading | saving */
  @Local transfer: string = ''
  @Local received: number = 0
  @Local total: number = 0
  private videoToken: string = ''
  private controller: VideoController = new VideoController()
  private web: webview.WebviewController = new webview.WebviewController()
  /** The copy fetched into the app cache, once there is one. */
  private local: string = ''

  aboutToAppear(): void {
    this.load()
  }

  aboutToDisappear(): void {
    this.stopVideo()
  }

  /** A link inside the previewed file points this same view at another file. */
  @Monitor('path', 'root')
  onTargetChange(): void {
    this.stopVideo()
    this.loading = true
    this.kind = ''
    this.text = ''
    this.truncated = false
    this.imageData = ''
    this.videoUrl = ''
    this.pdfSrc = ''
    this.web = new webview.WebviewController()
    this.note = ''
    this.error = ''
    this.rendered = true
    this.local = ''
    this.transfer = ''
    this.load()
  }

  private stopVideo(): void {
    if (this.videoToken.length > 0 && app.api !== null) {
      app.api.stopVideoPreview(this.videoToken)
    }
    this.videoToken = ''
  }

  get rel(): string {
    return relPath(this.root, this.path)
  }

  get name(): string {
    return this.path.split('/').pop() ?? ''
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  async load(): Promise<void> {
    const api = app.api
    if (api === null) {
      return
    }
    const ext = extOf(this.path)
    const path = this.path
    try {
      if (IMAGE_EXT.includes(ext)) {
        const b64 = await api.readFileBase64(this.root, this.rel, MAX_IMAGE)
        if (path !== this.path) {
          return
        }
        this.imageData = `data:image/${ext === 'jpg' ? 'jpeg' : ext};base64,${b64}`
        this.kind = 'image'
      } else if (VIDEO_EXT.includes(ext)) {
        const token = await api.startVideoPreview(this.root, this.rel)
        if (path !== this.path) {
          api.stopVideoPreview(token)
          return
        }
        this.videoToken = token
        this.videoUrl = api.c.videoUrl(token)
        this.kind = 'video'
      } else if (ext === 'pdf') {
        // The system web view renders a PDF from a file in the app sandbox,
        // so fetch a copy first; the same copy is what Save hands over.
        const local = await this.fetchLocal()
        if (path !== this.path) {
          return
        }
        this.transfer = ''
        this.pdfSrc = localFileUrl(local)
        this.kind = 'pdf'
      } else if (BINARY_EXT.includes(ext)) {
        this.note = L('This type of file cannot be shown here. Save it, or open it in another app.',
          '这种文件无法在这里显示，可以保存到设备，或用其他应用打开。')
        this.kind = 'file'
      } else {
        const full = await api.readFile(this.root, this.rel)
        if (path !== this.path) {
          return
        }
        this.truncated = full.length > MAX_TEXT
        this.text = this.truncated ? full.substring(0, MAX_TEXT) : full
        this.kind = 'text'
      }
    } catch (e) {
      if (path !== this.path) {
        return
      }
      this.transfer = ''
      if (e instanceof ApiError && (e as ApiError).isNotFound) {
        this.error = L(`The server has no file at ${this.path}`, `服务器上没有这个文件：${this.path}`)
      } else if (errorText(e) === 'Path is not a file') {
        this.error = L(`${this.path} is a folder, not a file.`, `${this.path} 是一个文件夹，不是文件。`)
      } else {
        // Binary content, too large to preview, and so on: it can still be saved.
        this.note = errorText(e)
        this.kind = 'file'
      }
    } finally {
      if (path === this.path) {
        this.loading = false
      }
    }
  }

  /** Fetches the file into the app cache (once), reporting progress. */
  private async fetchLocal(): Promise<string> {
    if (this.local.length > 0 && fs.accessSync(this.local)) {
      return this.local
    }
    const api = app.api
    if (api === null) {
      throw new ApiError(0, 'network', L('Not connected to a server', '未连接服务器'))
    }
    const path = this.path
    const base = downloadsDir(this.ctx().cacheDir)
    pruneDownloads(base)
    const dest = `${cacheFolder(base, path)}/${this.name}`
    this.received = 0
    this.total = 0
    this.transfer = 'downloading'
    let shownAt = 0
    await downloadWorkspaceFile(api.c, this.root, this.rel, dest, (got: number, of: number) => {
      // Chunks arrive many times a second; redraw a few times a second.
      const now = Date.now()
      if (path === this.path && (now - shownAt > 150 || got === of)) {
        shownAt = now
        this.received = got
        this.total = of
      }
    })
    if (path === this.path) {
      this.local = dest
    }
    return dest
  }

  async saveToDevice(): Promise<void> {
    if (this.transfer.length > 0) {
      return
    }
    try {
      const local = await this.fetchLocal()
      const opts = new picker.DocumentSaveOptions()
      opts.newFileNames = [this.name]
      const uris = await new picker.DocumentViewPicker(this.ctx()).save(opts)
      if (uris.length === 0) {
        return
      }
      this.transfer = 'saving'
      await copyFileInto(local, uris[0])
      toast(L(`Saved ${this.name}`, `已保存 ${this.name}`))
    } catch (e) {
      toast(L(`Could not save: ${errorText(e)}`, `保存失败：${errorText(e)}`))
    } finally {
      this.transfer = ''
    }
  }

  async openInAnotherApp(): Promise<void> {
    if (this.transfer.length > 0) {
      return
    }
    let local = ''
    try {
      local = await this.fetchLocal()
    } catch (e) {
      toast(L(`Could not download: ${errorText(e)}`, `下载失败：${errorText(e)}`))
      return
    } finally {
      this.transfer = ''
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: fileUri.getUriFromPath(local),
        type: mimeFor(this.name),
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      }
      await this.ctx().startAbility(want)
    } catch (e) {
      toast(L('No app on this device opened this file. Save it instead.', '设备上没有应用能打开这个文件，可以改为保存。'))
    }
  }

  /** Hands the download to the system browser through a short-lived link. */
  async downloadInBrowser(): Promise<void> {
    const api = app.api
    if (api === null) {
      return
    }
    try {
      await this.ctx().openLink(await api.browserDownloadUrl(this.root, this.rel))
    } catch (e) {
      toast(L(`Could not open the browser: ${errorText(e)}`, `无法打开浏览器：${errorText(e)}`))
    }
  }

  @Builder
  moreMenu() {
    Menu() {
      MenuItem({ content: L('Save to device', '保存到设备') }).onClick(() => {
        this.saveToDevice()
      })
      MenuItem({ content: L('Open in another app', '用其他应用打开') }).onClick(() => {
        this.openInAnotherApp()
      })
      MenuItem({ content: L('Download in browser', '用浏览器下载') }).onClick(() => {
        this.downloadInBrowser()
      })
      MenuItem({ content: L('Copy path', '复制路径') }).onClick(() => copyText(this.path))
    }
  }

  @Builder
  transferBar() {
    Column({ space: 4 }) {
      if (this.transfer === 'downloading' && this.total > 0) {
        Progress({ value: this.received, total: this.total, type: ProgressType.Linear })
          .color($r('app.color.accent')).width('100%')
      } else {
        Progress({ value: 0, total: 100, type: ProgressType.Linear }).color($r('app.color.accent')).width('100%')
      }
      Text(this.transfer === 'saving' ? L('Saving…', '正在保存…') :
        this.total > 0 ? L(`Downloading ${formatBytes(this.received)} of ${formatBytes(this.total)}`,
          `正在下载 ${formatBytes(this.received)} / ${formatBytes(this.total)}`) :
        L(`Downloading ${formatBytes(this.received)}`, `正在下载 ${formatBytes(this.received)}`))
        .fontSize(11).fontColor($r('app.color.text3'))
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 2, bottom: 6 })
    .width('100%')
  }

  /** The system viewer could not show the PDF: fall back to the file card, with the reason. */
  private pdfFailed(result: PdfLoadResult): void {
    this.note = result === PdfLoadResult.PARSE_ERROR_PASSWORD ?
    L('This PDF is password-protected. Open it in another app that can ask for the password.',
      '这个 PDF 有密码保护，请用能输入密码的其他应用打开。') :
    L('This PDF could not be displayed here. Save it, or open it in another app.',
      '这个 PDF 无法在这里显示，可以保存到设备，或用其他应用打开。')
    this.kind = 'file'
  }

  /** For a file with no inline preview: what it is, and the two things that can be done with it. */
  @Builder
  fileCard() {
    Column({ space: 14 }) {
      SymbolGlyph(sym(fileIconFor(this.name))).fontSize(52).fontColor([$r('app.color.accent')])
      Text(this.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text'))
        .textAlign(TextAlign.Center)
      if (this.note.length > 0) {
        Text(this.note).fontSize(13).fontColor($r('app.color.text3')).textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: 360 })
      }
      Button(L('Save to device', '保存到设备')).type(ButtonType.Capsule).height(44).width(240)
        .backgroundColor($r('app.color.accent')).enabled(this.transfer.length === 0)
        .onClick(() => {
          this.saveToDevice()
        })
      Button(L('Open in another app', '用其他应用打开')).type(ButtonType.Capsule).height(44).width(240)
        .fontColor($r('app.color.text')).backgroundColor($r('app.color.surface2'))
        .enabled(this.transfer.length === 0)
        .onClick(() => {
          this.openInAnotherApp()
        })
    }
    .width('100%')
    .padding(28)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Row({ space: 2 }) {
        IconButton({ icon: 'chevron_left', sz: 22, color: $r('app.color.text'), onTap: () => this.onClose() })
        Column() {
          Text(this.name).fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.lineNo > 0 ? `${this.rel}:${this.lineNo}` : this.rel).fontSize(11).fontFamily('monospace')
            .fontColor($r('app.color.text3')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 4 })
        if (extOf(this.path) === 'md' && this.text.length > 0) {
          IconButton({ icon: this.rendered ? 'doc_plaintext' : 'doc_text', sz: 18, onTap: () => {
            this.rendered = !this.rendered
          } })
        }
        if (!this.loading && this.error.length === 0) {
          IconButton({ icon: 'square_and_arrow_down', sz: 19, enabledBtn: this.transfer.length === 0, onTap: () => {
            this.saveToDevice()
          } })
          // A built-in Button: bindMenu opens on tap by itself.
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph(sym('dot_grid_1x2')).fontSize(19).fontColor([$r('app.color.text2')])
          }
          .width(40).height(40).backgroundColor(Color.Transparent)
          .bindMenu(this.moreMenu())
        }
      }.padding({ left: 6, right: 6, top: 6, bottom: 6 }).width('100%')

      if (this.transfer.length > 0) {
        this.transferBar()
      }

      if (this.loading) {
        Loading().layoutWeight(1)
      } else if (this.error.length > 0) {
        EmptyState({ icon: 'exclamationmark_triangle', title: L('Cannot open this file', '无法打开这个文件'),
          message: this.error }).layoutWeight(1)
      } else if (this.kind === 'image') {
        Image(this.imageData).objectFit(ImageFit.Contain).width('100%').layoutWeight(1)
          .draggable(false)
      } else if (this.kind === 'video') {
        Video({ src: this.videoUrl, controller: this.controller })
          .width('100%').layoutWeight(1).autoPlay(true).controls(true).objectFit(ImageFit.Contain)
          .onError(() => {
            toast(L('This video cannot be played here. Save it, or open it in another app.',
              '这个视频无法在这里播放，可以保存到设备，或用其他应用打开。'))
          })
      } else if (this.kind === 'pdf') {
        // `toolbar=0` hides the viewer's own bar; saving is in the header above.
        Web({ src: `${this.pdfSrc}#toolbar=0&navpanes=0`, controller: this.web })
          .fileAccess(true)
          .domStorageAccess(true)
          .width('100%')
          .layoutWeight(1)
          .onPdfLoadEvent((e: OnPdfLoadEvent) => {
            if (e.result !== PdfLoadResult.LOAD_SUCCESS) {
              this.pdfFailed(e.result)
            }
          })
      } else if (this.kind === 'text') {
        if (this.truncated) {
          Text(L(`Showing the first ${MAX_TEXT} characters. Save the file to read all of it.`,
            `只显示了前 ${MAX_TEXT} 个字符，保存文件后可查看全部内容。`))
            .fontSize(12).fontColor($r('app.color.text3')).padding({ left: 14, right: 14, bottom: 4 }).width('100%')
        }
        Scroll() {
          Column() {
            if (extOf(this.path) === 'md' && this.rendered) {
              MarkdownView({ text: this.text, rootPath: this.root })
            } else {
              CodeBlock({ code: this.text, lang: extOf(this.path) })
            }
          }.padding(14)
        }.layoutWeight(1).align(Alignment.TopStart).width('100%')
      } else {
        Scroll() {
          this.fileCard()
        }.layoutWeight(1).width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}

/** Directory browser rooted at a folder. */
@ComponentV2
export struct FilesView {
  @Param folder: FolderDetail | null = null
  @Event onPreview: (path: string) => void = (p: string) => {
  }
  @Local path: string = ''
  @Local entries: DirEntry[] = []
  @Local loading: boolean = false
  @Local error: string = ''

  aboutToAppear(): void {
    this.path = this.folder?.path ?? ''
    this.load()
  }

  async load(): Promise<void> {
    const api = app.api
    if (api === null || this.path.length === 0) {
      return
    }
    this.loading = true
    this.error = ''
    try {
      const list = await api.directoryWithFiles(this.path)
      this.entries = list.sort((a: DirEntry, b: DirEntry) => a.isDir === b.isDir ?
      a.name.localeCompare(b.name) : (a.isDir ? -1 : 1))
    } catch (e) {
      this.error = errorText(e)
    } finally {
      this.loading = false
    }
  }

  up(): void {
    const root = this.folder?.path ?? ''
    if (this.path === root) {
      return
    }
    const i = this.path.lastIndexOf('/')
    this.path = i > 0 ? this.path.substring(0, i) : root
    if (!this.path.startsWith(root)) {
      this.path = root
    }
    this.load()
  }

  confirmDelete(e: DirEntry): void {
    this.getUIContext().showAlertDialog({
      title: L('Delete?', '删除？'),
      message: e.name,
      primaryButton: { value: L('Cancel', '取消'), action: () => {
      } },
      secondaryButton: {
        value: L('Delete', '删除'), fontColor: $r('app.color.danger'), action: async () => {
          try {
            await app.api?.deleteEntry(this.folder?.path ?? '', relPath(this.folder?.path ?? '', e.path))
            this.load()
          } catch (err) {
            toast(errorText(err))
          }
        }
      }
    })
  }

  @Builder
  entryMenu(e: DirEntry) {
    Menu() {
      MenuItem({ content: L('Delete', '删除') }).onClick(() => this.confirmDelete(e))
    }
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        if (this.path !== (this.folder?.path ?? '')) {
          IconButton({ icon: 'arrow_up', sz: 17, box: 32, onTap: () => this.up() })
        }
        Text(relPath(this.folder?.path ?? '', this.path).length > 0 ? relPath(this.folder?.path ?? '', this.path) : '/')
          .fontSize(13).fontFamily('monospace').fontColor($r('app.color.text2')).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        IconButton({ icon: 'arrow_clockwise', sz: 17, box: 32, onTap: () => {
          this.load()
        } })
      }.padding({ left: 14, right: 8, top: 4, bottom: 4 }).width('100%')

      if (this.loading && this.entries.length === 0) {
        Loading().layoutWeight(1)
      } else if (this.error.length > 0) {
        EmptyState({ icon: 'exclamationmark_triangle', title: L('Cannot list files', '无法列出文件'), message: this.error })
          .layoutWeight(1)
      } else {
        List() {
          ForEach(this.entries, (e: DirEntry) => {
            ListItem() {
              Row({ space: 12 }) {
                SymbolGlyph(sym(e.isDir ? 'folder_fill' : fileIconFor(e.name))).fontSize(20)
                  .fontColor([e.isDir ? $r('app.color.accent') : $r('app.color.text3')])
                Text(e.name).fontSize(15).fontColor($r('app.color.text')).layoutWeight(1).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (!e.isDir && e.size !== undefined) {
                  Text(formatBytes(e.size)).fontSize(11).fontColor($r('app.color.text3'))
                }
                if (e.isDir) {
                  SymbolGlyph(sym('chevron_right')).fontSize(13).fontColor([$r('app.color.text3')])
                }
              }
              .padding({ left: 16, right: 16, top: 11, bottom: 11 })
              .width('100%')
              .onClick(() => {
                if (e.isDir) {
                  this.path = e.path
                  this.load()
                } else {
                  this.onPreview(e.path)
                }
              })
              .bindContextMenu(this.entryMenu(e), ResponseType.LongPress)
            }
          }, (e: DirEntry) => e.path)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: $r('app.color.border'), startMargin: 48 })
      }
    }
    .width('100%')
    .height('100%')
  }
}

