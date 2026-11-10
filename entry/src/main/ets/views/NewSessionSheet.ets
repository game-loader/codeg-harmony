import { app } from '../store/AppState'
import { AgentInfo, FolderDetail } from '../model/Models'
import { L } from '../common/I18n'
import { AgentAvatar, sym } from '../components/Common'

@ComponentV2
export struct NewSessionSheet {
  @Param presetFolder: number = -1
  @Event onStart: (agentType: string, folder: FolderDetail | null) => void = (a: string, f: FolderDetail | null) => {
  }
  @Local agent: string = ''
  @Local folderId: number = 0

  aboutToAppear(): void {
    this.folderId = this.presetFolder >= 0 ? this.presetFolder : 0
    this.agent = app.defaultAgent(app.folderById(this.folderId))
  }

  get projects(): FolderDetail[] {
    return app.folders.filter((f: FolderDetail) => !f.isChat)
      .sort((a: FolderDetail, b: FolderDetail) => b.lastOpenedAt - a.lastOpenedAt)
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
      this.folderId = id
    })
  }

  build() {
    Column({ space: 12 }) {
      Text(L('New session', '新建会话')).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .padding({ left: 20 }).width('100%')
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
              this.agent = a.agentType
            })
          }, (a: AgentInfo) => a.agentType)
        }.padding({ left: 20, right: 20 })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

      Text(L('Workspace', '工作区')).fontSize(12).fontColor($r('app.color.text3')).padding({ left: 20 }).width('100%')
      List({ space: 2 }) {
        ListItem() {
          this.folderRow(0, 'message', L('No folder (chat)', '无目录（对话）'), L('A scratch directory on the server',
            '服务器上的临时目录'))
        }
        ForEach(this.projects, (f: FolderDetail) => {
          ListItem() {
            this.folderRow(f.id, f.isWorktree ? 'rectangle_split_3x1' : 'folder_fill', f.displayName, f.path)
          }
        }, (f: FolderDetail) => `${f.id}`)
      }.layoutWeight(1).padding({ left: 8, right: 8 }).scrollBar(BarState.Off)

      Button(L('Start', '开始')).type(ButtonType.Capsule).height(48).width('90%')
        .backgroundColor($r('app.color.accent')).enabled(this.agent.length > 0)
        .onClick(() => this.onStart(this.agent, this.folderId > 0 ? app.folderById(this.folderId) : null))
        .margin({ bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 8 })
  }
}
