import { app } from '../store/AppState'
import { DirEntry, FolderDetail } from '../model/Models'
import { errorText } from '../net/ApiError'
import { L, formatBytes } from '../common/I18n'
import { EmptyState, IconButton, Loading, sym, toast } from '../components/Common'
import { CodeBlock, MarkdownView } from '../components/Markdown'
import { fileIconFor } from '../components/MarkdownParse'

const IMAGE_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg', 'heic']
const VIDEO_EXT = ['mp4', 'm4v', 'mov', '3gp', '3g2', 'webm', 'mkv']
const MAX_IMAGE = 15000000

export function extOf(p: string): string {
  return (p.split('.').pop() ?? '').toLowerCase()
}

export function relPath(root: string, abs: string): string {
  const r = root.endsWith('/') ? root : root + '/'
  return abs.startsWith(r) ? abs.substring(r.length) : abs.replace(new RegExp('^/+'), '')
}

/** Previews one workspace file: text, markdown, image or video. */
@ComponentV2
export struct FilePreview {
  @Param root: string = ''
  @Param path: string = ''
  @Event onClose: () => void = () => {
  }
  @Local loading: boolean = true
  @Local text: string = ''
  @Local imageData: string = ''
  @Local videoUrl: string = ''
  @Local error: string = ''
  @Local rendered: boolean = true
  private videoToken: string = ''
  private controller: VideoController = new VideoController()

  aboutToAppear(): void {
    this.load()
  }

  aboutToDisappear(): void {
    if (this.videoToken.length > 0 && app.api !== null) {
      app.api.stopVideoPreview(this.videoToken)
    }
  }

  get rel(): string {
    return relPath(this.root, this.path)
  }

  async load(): Promise<void> {
    const api = app.api
    if (api === null) {
      return
    }
    const ext = extOf(this.path)
    try {
      if (IMAGE_EXT.includes(ext) && ext !== 'svg') {
        const b64 = await api.readFileBase64(this.root, this.rel, MAX_IMAGE)
        this.imageData = `data:image/${ext === 'jpg' ? 'jpeg' : ext};base64,${b64}`
      } else if (VIDEO_EXT.includes(ext)) {
        this.videoToken = await api.startVideoPreview(this.root, this.rel)
        this.videoUrl = api.c.videoUrl(this.videoToken)
      } else if (ext === 'pdf') {
        this.error = L('PDF preview is not supported here yet; open it on the desktop.',
          '暂不支持在此预览 PDF，请在桌面端打开。')
      } else {
        this.text = await api.readFile(this.root, this.rel)
      }
    } catch (e) {
      this.error = errorText(e)
    } finally {
      this.loading = false
    }
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        IconButton({ icon: 'chevron_left', sz: 22, color: $r('app.color.text'), onTap: () => this.onClose() })
        Column() {
          Text(this.path.split('/').pop() ?? '').fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.rel).fontSize(11).fontFamily('monospace').fontColor($r('app.color.text3')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (extOf(this.path) === 'md' && this.text.length > 0) {
          IconButton({ icon: this.rendered ? 'doc_plaintext' : 'doc_text', sz: 18, onTap: () => {
            this.rendered = !this.rendered
          } })
        }
      }.padding({ left: 6, right: 8, top: 6, bottom: 6 }).width('100%')

      if (this.loading) {
        Loading().layoutWeight(1)
      } else if (this.error.length > 0) {
        EmptyState({ icon: 'exclamationmark_triangle', title: L('Cannot preview', '无法预览'), message: this.error })
          .layoutWeight(1)
      } else if (this.imageData.length > 0) {
        Image(this.imageData).objectFit(ImageFit.Contain).width('100%').layoutWeight(1)
          .draggable(false)
      } else if (this.videoUrl.length > 0) {
        Video({ src: this.videoUrl, controller: this.controller })
          .width('100%').layoutWeight(1).autoPlay(true).controls(true).objectFit(ImageFit.Contain)
          .onError(() => {
            toast(L('This video format cannot be played', '无法播放此视频格式'))
          })
      } else {
        Scroll() {
          Column() {
            if (extOf(this.path) === 'md' && this.rendered) {
              MarkdownView({ text: this.text, rootPath: this.root })
            } else {
              CodeBlock({ code: this.text, lang: extOf(this.path) })
            }
          }.padding(14)
        }.layoutWeight(1).align(Alignment.TopStart).width('100%')
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

