import { app } from '../store/AppState'
import { AgentInfo, FolderDetail } from '../model/Models'
import { AgentOptionsModel } from '../session/AgentOptionsModel'
import { L } from '../common/I18n'
import { agentName } from '../common/Agents'
import { AgentAvatar, sym } from '../components/Common'
import { OptionRows } from '../components/AgentOptionsPanel'

@ComponentV2
export struct NewSessionSheet {
  @Param presetFolder: number = -1
  @Event onStart: (agentType: string, folder: FolderDetail | null) => void = (a: string, f: FolderDetail | null) => {
  }
  @Local agent: string = ''
  @Local folderId: number = 0
  @Local showMore: boolean = false
  /** What the chosen agent offers; picks are saved and the new session starts with them. */
  private opts: AgentOptionsModel = new AgentOptionsModel()

  aboutToAppear(): void {
    this.folderId = this.presetFolder >= 0 ? this.presetFolder : 0
    this.agent = app.defaultAgent(app.folderById(this.folderId))
    this.loadOptions(false)
  }

  get projects(): FolderDetail[] {
    return app.folders.filter((f: FolderDetail) => !f.isChat)
      .sort((a: FolderDetail, b: FolderDetail) => b.lastOpenedAt - a.lastOpenedAt)
  }

  folder(): FolderDetail | null {
    return this.folderId > 0 ? app.folderById(this.folderId) : null
  }

  /** Reads the options of the chosen agent in the chosen folder (project settings can change the defaults). */
  loadOptions(force: boolean): void {
    const api = app.api
    if (api === null || this.agent.length === 0) {
      return
    }
    this.opts.prepareDraft(api, this.agent, this.folder()?.path, force)
  }

  @Builder
  folderRow(id: number, icon: string, title: string, sub: string) {
    Row({ space: 10 }) {
      SymbolGlyph(sym(icon)).fontSize(18).fontColor([$r('app.color.accent')])
      Column({ space: 1 }) {
        Text(title).fontSize(14.5).fontColor($r('app.color.text')).maxLines(1)
        if (sub.length > 0) {
          Text(sub).fontSize(11).fontColor($r('app.color.text3')).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (this.folderId === id) {
        SymbolGlyph(sym('checkmark')).fontSize(16).fontColor([$r('app.color.accent')])
      }
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .width('100%')
    .borderRadius(12)
    .backgroundColor(this.folderId === id ? $r('app.color.accent_soft') : Color.Transparent)
    .onClick(() => {
      if (this.folderId !== id) {
        this.folderId = id
        this.loadOptions(false)
      }
    })
  }

  /** Model and mode up front; the agent's other options behind "More options". */
  @Builder
  optionsSection() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(L('Model & mode', '模型与模式')).fontSize(12).fontColor($r('app.color.text3'))
        if (this.opts.phase === 'loading') {
          LoadingProgress().width(14).height(14).color($r('app.color.accent'))
        }
      }
      if (this.opts.phase === 'error') {
        Column({ space: 6 }) {
          Text(this.opts.error).fontSize(13).fontColor($r('app.color.danger')).copyOption(CopyOptions.LocalDevice)
          Text(L('Try again', '重试')).fontSize(13).fontColor($r('app.color.accent'))
            .padding({ top: 4, bottom: 4 })
            .onClick(() => this.loadOptions(true))
        }
        .alignItems(HorizontalAlign.Start)
        .padding(12).width('100%').borderRadius(12).backgroundColor($r('app.color.danger_soft'))
      } else if (this.opts.options === null) {
        Text(L(`Reading the options ${agentName(this.agent)} offers…`, `正在读取 ${agentName(this.agent)} 提供的选项…`))
          .fontSize(13).fontColor($r('app.color.text3'))
      } else if (this.opts.options.rows.length === 0) {
        Text(L('This agent has no selectable options', '该智能体没有可选项')).fontSize(13)
          .fontColor($r('app.color.text3'))
      } else {
        OptionRows({
          opts: this.opts, part: 'primary', onPick: (k: string, v: string) => {
            this.opts.pick(k, v)
          }
        })
        if (this.opts.options.moreRows.length > 0) {
          Row({ space: 4 }) {
            Text(this.showMore ? L('Fewer options', '收起选项') :
            L(`More options (${this.opts.options.moreRows.length})`, `更多选项（${this.opts.options.moreRows.length}）`))
              .fontSize(13).fontColor($r('app.color.accent'))
            SymbolGlyph(sym(this.showMore ? 'chevron_up' : 'chevron_down')).fontSize(11)
              .fontColor([$r('app.color.accent')])
          }
          .padding({ top: 2, bottom: 6 })
          .onClick(() => {
            this.showMore = !this.showMore
          })
          if (this.showMore) {
            OptionRows({
              opts: this.opts, part: 'more', onPick: (k: string, v: string) => {
                this.opts.pick(k, v)
              }
            })
          }
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20 })
    .width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Text(L('New session', '新建会话')).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .padding({ left: 20 }).width('100%')
      Scroll() {
        Column({ space: 12 }) {
          Text(L('Agent', '智能体')).fontSize(12).fontColor($r('app.color.text3')).padding({ left: 20 }).width('100%')
          Scroll() {
            Row({ space: 10 }) {
              ForEach(app.enabledAgents, (a: AgentInfo) => {
                Column({ space: 6 }) {
                  AgentAvatar({ agent: a.agentType, sz: 40 })
                  Text(a.name).fontSize(11.5).maxLines(1).constraintSize({ maxWidth: 76 })
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontColor(this.agent === a.agentType ? $r('app.color.accent') : $r('app.color.text2'))
                }
                .padding(8)
                .borderRadius(14)
                .border({ width: 1.5, color: this.agent === a.agentType ? $r('app.color.accent') : Color.Transparent })
                .backgroundColor(this.agent === a.agentType ? $r('app.color.accent_soft') : $r('app.color.surface2'))
                .opacity(a.available ? 1 : 0.5)
                .onClick(() => {
                  if (this.agent !== a.agentType) {
                    this.agent = a.agentType
                    this.showMore = false
                    this.loadOptions(false)
                  }
                })
              }, (a: AgentInfo) => a.agentType)
            }.padding({ left: 20, right: 20 })
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

          this.optionsSection()

          Text(L('Workspace', '工作区')).fontSize(12).fontColor($r('app.color.text3')).padding({ left: 20 }).width('100%')
          Column({ space: 2 }) {
            this.folderRow(0, 'message', L('No folder (chat)', '无目录（对话）'), L('A scratch directory on the server',
              '服务器上的临时目录'))
            ForEach(this.projects, (f: FolderDetail) => {
              this.folderRow(f.id, f.isWorktree ? 'rectangle_split_3x1' : 'folder_fill', f.displayName, f.path)
            }, (f: FolderDetail) => `${f.id}`)
          }.padding({ left: 8, right: 8 }).width('100%')
        }
        .width('100%')
        .padding({ bottom: 8 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      Button(L('Start', '开始')).type(ButtonType.Capsule).height(48).width('90%')
        .backgroundColor($r('app.color.accent')).enabled(this.agent.length > 0)
        .onClick(() => this.onStart(this.agent, this.folder()))
        .margin({ bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 8 })
  }
}
