import { app } from '../store/AppState'
import { DirEntry, FolderDetail } from '../model/Models'
import { ApiError, errorText } from '../net/ApiError'
import { GitCredentials } from '../net/Api'
import { L } from '../common/I18n'
import { EmptyState, IconButton, Loading, sym, toast } from '../components/Common'

@ComponentV2
export struct ProjectRow {
  @Param folder: FolderDetail = new FolderDetail()
  @Param count: number = 0
  @Param running: number = 0
  @Param selected: boolean = false

  build() {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(sym(this.folder.isWorktree ? 'rectangle_split_3x1' : 'folder_fill')).fontSize(19)
          .fontColor([Color.White])
      }
      .width(38).height(38).borderRadius(11).justifyContent(FlexAlign.Center)
      .backgroundColor(this.folder.color.length > 0 ? this.folder.color : $r('app.color.accent'))

      Column({ space: 3 }) {
        Text(this.folder.displayName).fontSize(15.5).fontWeight(FontWeight.Medium).fontColor($r('app.color.text'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          if ((this.folder.gitBranch ?? '').length > 0) {
            Text(this.folder.gitBranch ?? '').fontSize(11.5).fontFamily('monospace').fontColor($r('app.color.accent2'))
              .maxLines(1).constraintSize({ maxWidth: 150 }).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(this.folder.path).fontSize(11.5).fontColor($r('app.color.text3')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        }.width('100%')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      Column({ space: 2 }) {
        Text(`${this.count}`).fontSize(13).fontColor($r('app.color.text2'))
        if (this.running > 0) {
          Text(L(`${this.running} live`, `${this.running} 运行`)).fontSize(10.5).fontColor($r('app.color.accent'))
        }
      }.alignItems(HorizontalAlign.End)
    }
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .margin({ left: 10, right: 10 })
    .borderRadius(14)
    .backgroundColor(this.selected ? $r('app.color.accent_soft') : Color.Transparent)
  }
}

/** Server-side directory picker used to open a folder or choose a clone target. */
@ComponentV2
export struct DirectoryPicker {
  @Param title: string = ''
  @Event onPick: (path: string) => void = (p: string) => {
  }
  @Local path: string = ''
  @Local entries: DirEntry[] = []
  @Local loading: boolean = true
  @Local error: string = ''

  async aboutToAppear(): Promise<void> {
    try {
      this.path = await app.api!.homeDirectory()
    } catch (e) {
      this.path = '/'
    }
    this.load()
  }

  async load(): Promise<void> {
    this.loading = true
    this.error = ''
    try {
      this.entries = (await app.api!.directoryEntries(this.path))
        .filter((e: DirEntry) => !e.name.startsWith('.'))
        .sort((a: DirEntry, b: DirEntry) => a.name.localeCompare(b.name))
    } catch (e) {
      this.error = errorText(e)
    } finally {
      this.loading = false
    }
  }

  up(): void {
    const i = this.path.replace(new RegExp('/+$'), '').lastIndexOf('/')
    this.path = i > 0 ? this.path.substring(0, i) : '/'
    this.load()
  }

  build() {
    Column() {
      Text(this.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .padding({ left: 20, top: 8, bottom: 8 }).width('100%')
      Row({ space: 6 }) {
        IconButton({ icon: 'arrow_up', sz: 17, box: 32, onTap: () => this.up() })
        Text(this.path).fontSize(12.5).fontFamily('monospace').fontColor($r('app.color.text2')).layoutWeight(1)
          .maxLines(2)
      }.padding({ left: 12, right: 12 }).width('100%')
      if (this.loading) {
        Loading().layoutWeight(1)
      } else if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor($r('app.color.danger')).padding(20).layoutWeight(1)
      } else {
        List() {
          ForEach(this.entries, (e: DirEntry) => {
            ListItem() {
              Row({ space: 10 }) {
                SymbolGlyph(sym('folder_fill')).fontSize(18).fontColor([$r('app.color.accent')])
                Text(e.name).fontSize(15).fontColor($r('app.color.text')).layoutWeight(1).maxLines(1)
                SymbolGlyph(sym('chevron_right')).fontSize(12).fontColor([$r('app.color.text3')])
              }
              .padding({ left: 18, right: 16, top: 11, bottom: 11 })
              .width('100%')
              .onClick(() => {
                this.path = e.path
                this.load()
              })
            }
          }, (e: DirEntry) => e.path)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: $r('app.color.border'), startMargin: 46 })
      }
      Button(L('Use this folder', '使用此目录')).type(ButtonType.Capsule).height(46).width('90%')
        .backgroundColor($r('app.color.accent')).margin({ top: 8, bottom: 16 })
        .onClick(() => this.onPick(this.path))
    }
    .width('100%')
    .height('100%')
  }
}

@ComponentV2
export struct ProjectsList {
  @Param selectedId: number = 0
  @Event onOpen: (f: FolderDetail) => void = (f: FolderDetail) => {
  }
  @Local query: string = ''
  @Local showOpen: boolean = false
  @Local showClone: boolean = false
  @Local cloneUrl: string = ''
  @Local cloneDir: string = ''
  @Local cloneUser: string = ''
  @Local clonePass: string = ''
  @Local cloneNeedsAuth: boolean = false
  @Local cloning: boolean = false

  @Computed
  get list(): FolderDetail[] {
    const q = this.query.trim().toLowerCase()
    const roots = new Set<number>(app.folders.filter((f: FolderDetail) => !f.isWorktree).map((f: FolderDetail) => f.id))
    return app.folders.filter((f: FolderDetail) => !f.isChat)
      .filter((f: FolderDetail) => !(f.parentId !== undefined && roots.has(f.parentId)))
      .filter((f: FolderDetail) => q.length === 0 || f.displayName.toLowerCase().includes(q) ||
      f.path.toLowerCase().includes(q))
      .sort((a: FolderDetail, b: FolderDetail) => b.lastOpenedAt - a.lastOpenedAt)
  }

  running(id: number): number {
    return app.conversationsIn(id).filter((c) => c.status === 'in_progress').length
  }

  async openPath(path: string): Promise<void> {
    this.showOpen = false
    try {
      const f = await app.api!.openFolder(path)
      await app.refresh(true)
      this.onOpen(f)
    } catch (e) {
      toast(errorText(e))
    }
  }

  async clone(): Promise<void> {
    const url = this.cloneUrl.trim()
    const dir = this.cloneDir.trim()
    if (url.length === 0 || dir.length === 0) {
      toast(L('URL and target folder are required', '需要填写地址和目标目录'))
      return
    }
    this.cloning = true
    let cred: GitCredentials | undefined = undefined
    if (this.cloneNeedsAuth) {
      cred = new GitCredentials()
      cred.username = this.cloneUser
      cred.password = this.clonePass
    }
    try {
      await app.api!.cloneRepository(url, dir, cred)
      this.showClone = false
      await this.openPath(dir)
    } catch (e) {
      if (e instanceof ApiError && (e as ApiError).isGitAuth) {
        this.cloneNeedsAuth = true
        toast(L('Authentication required', '需要认证'))
      } else {
        toast(errorText(e))
      }
    } finally {
      this.cloning = false
    }
  }

  @Builder
  openSheet() {
    DirectoryPicker({ title: L('Open folder', '打开目录'), onPick: (p: string) => {
      this.openPath(p)
    } })
  }

  @Builder
  cloneSheet() {
    Column({ space: 10 }) {
      Text(L('Clone repository', '克隆仓库')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      TextInput({ text: this.cloneUrl, placeholder: 'https://github.com/owner/repo.git' }).height(44)
        .type(InputType.URL).backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.cloneUrl = v
          if (this.cloneDir.length === 0 || this.cloneDir.endsWith('/')) {
            const name = (v.split('/').pop() ?? '').replace(new RegExp('\\.git$'), '')
            this.cloneDir = `~/${name}`
          }
        })
      TextInput({ text: this.cloneDir, placeholder: L('Target folder (absolute)', '目标目录（绝对路径）') })
        .height(44).backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.cloneDir = v
        })
      if (this.cloneNeedsAuth) {
        TextInput({ placeholder: L('Username', '用户名') }).height(44).backgroundColor($r('app.color.surface2'))
          .onChange((v: string) => {
            this.cloneUser = v
          })
        TextInput({ placeholder: L('Password or token', '密码或令牌') }).type(InputType.Password).height(44)
          .backgroundColor($r('app.color.surface2'))
          .onChange((v: string) => {
            this.clonePass = v
          })
      }
      Button(this.cloning ? L('Cloning…', '克隆中…') : L('Clone', '克隆')).type(ButtonType.Capsule).height(44)
        .width('100%').backgroundColor($r('app.color.accent')).enabled(!this.cloning)
        .onClick(() => {
          this.clone()
        })
    }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Text(L('Projects', '项目')).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
          .layoutWeight(1)
        IconButton({ icon: 'arrow_down', sz: 19, onTap: () => {
          this.cloneNeedsAuth = false
          this.showClone = true
        } })
        IconButton({ icon: 'ohos_folder_badge_plus', sz: 20, color: $r('app.color.accent'), onTap: () => {
          this.showOpen = true
        } })
      }.padding({ left: 20, right: 10, top: 10, bottom: 6 }).width('100%')

      Search({ value: this.query, placeholder: L('Search projects', '搜索项目') }).height(40)
        .margin({ left: 16, right: 16, bottom: 6 }).backgroundColor($r('app.color.surface'))
        .onChange((v: string) => {
          this.query = v
        })

      if (app.loading && app.folders.length === 0) {
        Loading().layoutWeight(1)
      } else if (this.list.length === 0) {
        EmptyState({ icon: 'folder', title: L('No open projects', '没有已打开的项目'),
          message: L('Open a folder on the server to start.', '在服务器上打开一个目录即可开始。'),
          action: L('Open folder', '打开目录'), onAction: () => {
            this.showOpen = true
          } }).layoutWeight(1)
      } else {
        List({ space: 2 }) {
          ForEach(this.list, (f: FolderDetail) => {
            ListItem() {
              ProjectRow({ folder: f, count: app.conversationsIn(f.id).length, running: this.running(f.id),
                selected: f.id === this.selectedId })
                .onClick(() => this.onOpen(f))
            }
          }, (f: FolderDetail) => `${f.id}-${f.gitBranch ?? ''}-${app.conversationsIn(f.id).length}`)
          ListItem() {
            Column().height(90)
          }
        }.layoutWeight(1).scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .bindSheet($$this.showOpen, this.openSheet(), { height: SheetSize.LARGE, dragBar: true })
    .bindSheet($$this.showClone, this.cloneSheet(), { height: SheetSize.FIT_CONTENT, dragBar: true })
  }
}

