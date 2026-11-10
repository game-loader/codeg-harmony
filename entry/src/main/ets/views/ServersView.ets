import { app } from '../store/AppState'
import { ServerProfile } from '../store/ServerStore'
import { Api } from '../net/Api'
import { CodegClient } from '../net/CodegClient'
import { errorText } from '../net/ApiError'
import { L } from '../common/I18n'
import { Card, Divider1, IconButton, NavRow, PaneTitle, SectionHeader, sym, toast } from '../components/Common'

@ComponentV2
export struct ServerEditor {
  @Param editId: string = ''
  @Event onDone: () => void = () => {
  }
  @Local name: string = ''
  @Local url: string = ''
  @Local token: string = ''
  @Local testing: boolean = false
  @Local result: string = ''
  @Local ok: boolean = false

  aboutToAppear(): void {
    const p = app.servers.find((s: ServerProfile) => s.id === this.editId)
    if (p !== undefined) {
      this.name = p.name
      this.url = p.url
    }
  }

  async test(): Promise<void> {
    const u = ServerProfile.normalize(this.url)
    if (u === null) {
      this.result = L('Invalid URL', '地址无效')
      this.ok = false
      return
    }
    this.testing = true
    this.result = ''
    const tok = this.token.length > 0 ? this.token : (this.editId.length > 0 ? app.tokenOf(this.editId) : '')
    try {
      const api = new Api(new CodegClient(u, tok))
      const h = await api.health()
      await api.openFolders()
      this.ok = true
      this.result = L(`Connected · codeg ${h.version}`, `连接成功 · codeg ${h.version}`)
    } catch (e) {
      this.ok = false
      this.result = errorText(e)
    } finally {
      this.testing = false
    }
  }

  save(): void {
    const u = ServerProfile.normalize(this.url)
    if (u === null) {
      toast(L('Invalid URL', '地址无效'))
      return
    }
    if (this.editId.length === 0 && this.token.length === 0) {
      toast(L('Token is required', '需要填写令牌'))
      return
    }
    const p = app.saveServer(this.name, u, this.token.length > 0 ? this.token : null,
      this.editId.length > 0 ? this.editId : undefined)
    app.activate(p.id)
    this.onDone()
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text(this.editId.length > 0 ? L('Edit server', '编辑服务器') : L('Add a codeg server', '添加 codeg 服务器'))
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        Text(L('Run codeg-server on your machine (for example over Tailscale), then enter its address and CODEG_TOKEN.',
          '在你的电脑上运行 codeg-server（例如通过 Tailscale），然后填写地址和 CODEG_TOKEN。'))
          .fontSize(13).fontColor($r('app.color.text3'))
        Column({ space: 6 }) {
          Text(L('Name', '名称')).fontSize(12).fontColor($r('app.color.text3'))
          TextInput({ text: this.name, placeholder: L('My workstation', '我的工作站') }).height(46)
            .backgroundColor($r('app.color.surface'))
            .onChange((v: string) => {
              this.name = v
            })
          Text(L('Server URL', '服务器地址')).fontSize(12).fontColor($r('app.color.text3')).margin({ top: 8 })
          TextInput({ text: this.url, placeholder: 'http://100.x.y.z:3080' }).height(46)
            .type(InputType.URL).backgroundColor($r('app.color.surface'))
            .onChange((v: string) => {
              this.url = v
            })
          Text(L('Token', '令牌')).fontSize(12).fontColor($r('app.color.text3')).margin({ top: 8 })
          TextInput({ text: this.token, placeholder: this.editId.length > 0 ? L('Leave blank to keep', '留空则保持不变') :
            'CODEG_TOKEN' }).height(46).type(InputType.Password).backgroundColor($r('app.color.surface'))
            .onChange((v: string) => {
              this.token = v
            })
        }.alignItems(HorizontalAlign.Start).width('100%')

        if (this.result.length > 0) {
          Row({ space: 8 }) {
            SymbolGlyph(sym(this.ok ? 'checkmark_circle_fill' : 'exclamationmark_triangle')).fontSize(16)
              .fontColor([this.ok ? $r('app.color.success') : $r('app.color.danger')])
            Text(this.result).fontSize(13).fontColor(this.ok ? $r('app.color.success') : $r('app.color.danger'))
              .layoutWeight(1)
          }.width('100%')
        }
        Row({ space: 12 }) {
          Button(this.testing ? L('Testing…', '测试中…') : L('Test connection', '测试连接'))
            .type(ButtonType.Capsule).height(44).layoutWeight(1).fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.accent_soft')).enabled(!this.testing)
            .onClick(() => {
              this.test()
            })
          Button(L('Save', '保存')).type(ButtonType.Capsule).height(44).layoutWeight(1)
            .backgroundColor($r('app.color.accent'))
            .onClick(() => this.save())
        }.width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(24)
      .width('100%')
      .constraintSize({ maxWidth: 560 })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor($r('app.color.bg'))
  }
}

@ComponentV2
export struct ServerList {
  @Event onEdit: (id: string) => void = (id: string) => {
  }
  @Event onAdd: () => void = () => {
  }

  build() {
    Column() {
      SectionHeader({ title: L('Servers', '服务器'), trailing: L('Add', '添加'), onTrailing: () => this.onAdd() })
      Column() {
      Card() {
        ForEach(app.servers, (s: ServerProfile, i: number) => {
          if (i > 0) {
            Divider1({ inset: 58 })
          }
          Row({ space: 12 }) {
            Row() {
              SymbolGlyph(sym('computer')).fontSize(17).fontColor([Color.White])
            }
            .width(30).height(30).borderRadius(8).justifyContent(FlexAlign.Center)
            .backgroundColor(s.id === app.activeId ? $r('app.color.accent') : $r('app.color.text3'))
            Column({ space: 2 }) {
              Text(s.name).fontSize(16).fontColor($r('app.color.text')).maxLines(1)
              Text(s.url).fontSize(12).fontColor($r('app.color.text3')).fontFamily('monospace').maxLines(1)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (s.id === app.activeId) {
              Circle().width(8).height(8).fill(app.online ? $r('app.color.success') : $r('app.color.danger'))
            }
            IconButton({ icon: 'square_and_pencil', sz: 17, box: 34, onTap: () => this.onEdit(s.id) })
          }
          .padding({ left: 16, right: 8, top: 10, bottom: 10 })
          .width('100%')
          .onClick(() => app.activate(s.id))
        }, (s: ServerProfile) => s.id)
      }
      }.padding({ left: 16, right: 16 })
    }
  }
}

/** First-run screen when no server is configured. */
@ComponentV2
export struct Onboarding {
  @Local adding: boolean = false

  build() {
    if (this.adding) {
      ServerEditor({ onDone: () => {
        this.adding = false
      } })
    } else {
      Column({ space: 18 }) {
        Image($r('app.media.app_icon')).width(96).height(96).borderRadius(24)
        Text('Codeg').fontSize(34).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        Text(L('Drive your coding agents from HarmonyOS. Connect to a codeg-server to see every session, project and machine.',
          '在鸿蒙设备上驱动你的编码智能体。连接 codeg-server，查看所有会话、项目与机器。'))
          .fontSize(15).fontColor($r('app.color.text2')).textAlign(TextAlign.Center).constraintSize({ maxWidth: 420 })
        Button(L('Connect a server', '连接服务器')).type(ButtonType.Capsule).height(48).width(240)
          .backgroundColor($r('app.color.accent')).fontSize(16)
          .onClick(() => {
            this.adding = true
          })
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(32)
      .backgroundColor($r('app.color.bg'))
    }
  }
}
