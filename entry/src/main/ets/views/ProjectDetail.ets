import { app } from '../store/AppState'
import { ConversationSummary, FolderDetail, GitWorktree } from '../model/Models'
import { errorText } from '../net/ApiError'
import { L } from '../common/I18n'
import { EmptyState, IconButton, Loading, sym, toast } from '../components/Common'
import { SessionRow } from './SessionsList'
import { FilesView } from './FilesView'
import { GitView } from './GitView'
import { TerminalView } from './TerminalView'

@ComponentV2
export struct WorktreesView {
  @Param folder: FolderDetail | null = null
  @Event onOpenFolder: (f: FolderDetail) => void = (f: FolderDetail) => {
  }
  @Local list: GitWorktree[] = []
  @Local loading: boolean = true
  @Local error: string = ''
  @Local branch: string = ''

  aboutToAppear(): void {
    this.load()
  }

  async load(): Promise<void> {
    this.loading = true
    try {
      this.list = await app.api!.worktrees(this.folder?.path ?? '')
      this.error = ''
    } catch (e) {
      this.error = errorText(e)
    } finally {
      this.loading = false
    }
  }

  async add(): Promise<void> {
    const b = this.branch.trim()
    const root = this.folder?.path ?? ''
    if (b.length === 0 || root.length === 0) {
      return
    }
    const parent = root.substring(0, root.lastIndexOf('/'))
    const name = root.substring(root.lastIndexOf('/') + 1)
    const target = `${parent}/${name}-${b.replace(new RegExp('[^A-Za-z0-9._-]', 'g'), '-')}`
    try {
      await app.api!.worktreeAdd(root, b, target)
      this.branch = ''
      toast(L('Worktree created', '已创建工作树'))
      this.load()
    } catch (e) {
      toast(errorText(e))
    }
  }

  async open(w: GitWorktree): Promise<void> {
    try {
      const f = await app.api!.openWorktreeFolder(w.path, this.folder?.id ?? 0)
      await app.refresh(true)
      this.onOpenFolder(f)
    } catch (e) {
      toast(errorText(e))
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        TextInput({ text: this.branch, placeholder: L('New worktree branch', '新工作树分支') }).height(40)
          .layoutWeight(1).backgroundColor($r('app.color.surface'))
          .onChange((v: string) => {
            this.branch = v
          })
        Button(L('Add', '添加')).type(ButtonType.Capsule).height(40).backgroundColor($r('app.color.accent'))
          .onClick(() => {
            this.add()
          })
      }.padding(12).width('100%')
      if (this.loading) {
        Loading().layoutWeight(1)
      } else if (this.error.length > 0) {
        EmptyState({ icon: 'exclamationmark_triangle', title: L('Worktrees unavailable', '无法获取工作树'),
          message: this.error }).layoutWeight(1)
      } else {
        List() {
          ForEach(this.list, (w: GitWorktree) => {
            ListItem() {
              Row({ space: 10 }) {
                SymbolGlyph(sym(w.isMain ? 'house' : 'rectangle_split_3x1')).fontSize(18)
                  .fontColor([$r('app.color.accent')])
                Column({ space: 2 }) {
                  Text(w.branch ?? L('(detached)', '（游离）')).fontSize(14.5).fontFamily('monospace')
                    .fontColor($r('app.color.text'))
                  Text(w.path).fontSize(11.5).fontColor($r('app.color.text3')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (!w.isMain) {
                  SymbolGlyph(sym('chevron_right')).fontSize(13).fontColor([$r('app.color.text3')])
                }
              }
              .padding({ left: 16, right: 16, top: 11, bottom: 11 })
              .width('100%')
              .onClick(() => {
                if (!w.isMain) {
                  this.open(w)
                }
              })
            }
          }, (w: GitWorktree) => w.path)
        }.layoutWeight(1).divider({ strokeWidth: 0.5, color: $r('app.color.border'), startMargin: 44 })
      }
    }.width('100%').height('100%')
  }
}

@ComponentV2
export struct ProjectDetail {
  @Param folder: FolderDetail | null = null
  @Param selectedConversation: number = 0
  @Param showBack: boolean = false
  @Event onBack: () => void = () => {
  }
  @Event onOpenConversation: (c: ConversationSummary) => void = (c: ConversationSummary) => {
  }
  @Event onNewSession: (f: FolderDetail) => void = (f: FolderDetail) => {
  }
  @Event onPreview: (root: string, path: string) => void = (r: string, p: string) => {
  }
  @Event onOpenFolder: (f: FolderDetail) => void = (f: FolderDetail) => {
  }
  @Local tab: number = 0

  @Builder
  tabBtn(i: number, icon: string, label: string) {
    Column({ space: 3 }) {
      SymbolGlyph(sym(icon)).fontSize(18)
        .fontColor([this.tab === i ? $r('app.color.accent') : $r('app.color.text3')])
      Text(label).fontSize(11).fontColor(this.tab === i ? $r('app.color.accent') : $r('app.color.text3'))
    }
    .layoutWeight(1)
    .padding({ top: 6, bottom: 6 })
    .borderRadius(12)
    .backgroundColor(this.tab === i ? $r('app.color.accent_soft') : Color.Transparent)
    .onClick(() => {
      this.tab = i
    })
  }

  build() {
    Column() {
      Row({ space: 6 }) {
        if (this.showBack) {
          IconButton({ icon: 'chevron_left', sz: 22, color: $r('app.color.text'), onTap: () => this.onBack() })
        }
        Column({ space: 2 }) {
          Text(this.folder?.displayName ?? '').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.folder?.path ?? '').fontSize(11.5).fontFamily('monospace').fontColor($r('app.color.text3'))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        IconButton({ icon: 'square_and_pencil', sz: 20, color: $r('app.color.accent'), onTap: () => {
          if (this.folder !== null) {
            this.onNewSession(this.folder)
          }
        } })
      }.padding({ left: this.showBack ? 6 : 20, right: 10, top: 8, bottom: 6 }).width('100%')

      Row({ space: 4 }) {
        this.tabBtn(0, 'message', L('Sessions', '会话'))
        this.tabBtn(1, 'doc_text', L('Files', '文件'))
        this.tabBtn(2, 'rectangle_split_3x1', 'Git')
        this.tabBtn(3, 'square_grid_2x2', L('Worktrees', '工作树'))
        this.tabBtn(4, 'keyboard', L('Terminal', '终端'))
      }.padding({ left: 10, right: 10, bottom: 6 }).width('100%')

      Column() {
        if (this.tab === 0) {
          if (app.conversationsIn(this.folder?.id ?? 0).length === 0) {
            EmptyState({ icon: 'message', title: L('No sessions yet', '还没有会话'),
              action: L('New session', '新建会话'), onAction: () => {
                if (this.folder !== null) {
                  this.onNewSession(this.folder)
                }
              } })
          } else {
            List({ space: 2 }) {
              ForEach(app.conversationsIn(this.folder?.id ?? 0), (c: ConversationSummary) => {
                ListItem() {
                  SessionRow({ conv: c, selected: c.id === this.selectedConversation })
                    .onClick(() => this.onOpenConversation(c))
                }
              }, (c: ConversationSummary) => `${c.id}-${c.updatedAt}-${c.status}`)
            }.height('100%').scrollBar(BarState.Off)
          }
        } else if (this.tab === 1) {
          FilesView({ folder: this.folder, onPreview: (p: string) => this.onPreview(this.folder?.path ?? '', p) })
        } else if (this.tab === 2) {
          GitView({ folder: this.folder })
        } else if (this.tab === 3) {
          WorktreesView({ folder: this.folder, onOpenFolder: (f: FolderDetail) => this.onOpenFolder(f) })
        } else {
          TerminalView({ cwd: this.folder?.path ?? '' })
        }
      }.layoutWeight(1).width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
