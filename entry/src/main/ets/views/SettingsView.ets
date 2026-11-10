import { app } from '../store/AppState'
import { AppPrefs } from '../store/ServerStore'
import { AgentInfo, QuickMessage } from '../model/Models'
import { errorText } from '../net/ApiError'
import { JObj, arr, asObj, bool, str } from '../common/Json'
import { L, isZh, setZh } from '../common/I18n'
import { Card, Divider1, IconButton, NavRow, SectionHeader, sym, toast, AgentAvatar } from '../components/Common'
import { ServerEditor, ServerList } from './ServersView'

@ComponentV2
export struct AgentsSettings {
  @Local busy: string = ''

  async toggle(a: AgentInfo, on: boolean): Promise<void> {
    try {
      await app.api!.setAgentEnabled(a, on)
      app.agents = await app.api!.agents()
    } catch (e) {
      toast(errorText(e))
    }
  }

  async check(a: AgentInfo): Promise<void> {
    this.busy = a.agentType
    try {
      const r = await app.api!.preflight(a.agentType)
      const ok = bool(r, 'passed', true)
      let msg = L('Check failed', '检查未通过')
      for (const c of arr(r, 'checks')) {
        const co = asObj(c)
        const st = str(co, 'status')
        if (st === 'fail') {
          msg = `${str(co, 'label')}: ${str(co, 'message')}`
          break
        }
      }
      toast(ok ? L(`${a.name} is ready`, `${a.name} 可用`) : msg)
    } catch (e) {
      toast(errorText(e))
    } finally {
      this.busy = ''
    }
  }

  build() {
    Column() {
      Card() {
        ForEach(app.agents, (a: AgentInfo, i: number) => {
          if (i > 0) {
            Divider1({ inset: 58 })
          }
          Row({ space: 12 }) {
            AgentAvatar({ agent: a.agentType, sz: 30 })
            Column({ space: 2 }) {
              Text(a.name).fontSize(15.5).fontColor($r('app.color.text'))
              Text([a.installedVersion ?? '', a.distributionType ?? '', a.available ? '' : L('not installed', '未安装')]
                .filter((s: string) => s.length > 0).join(' · '))
                .fontSize(12).fontColor($r('app.color.text3')).maxLines(1)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.busy === a.agentType) {
              LoadingProgress().width(18).height(18).color($r('app.color.accent'))
            } else {
              SymbolGlyph(sym('checkmark_circle')).fontSize(18).fontColor([$r('app.color.text3')])
                .onClick(() => {
                  this.check(a)
                })
            }
            Toggle({ type: ToggleType.Switch, isOn: a.enabled }).selectedColor($r('app.color.accent'))
              .onChange((v: boolean) => {
                this.toggle(a, v)
              })
          }.padding({ left: 14, right: 12, top: 10, bottom: 10 }).width('100%')
        }, (a: AgentInfo) => `${a.agentType}-${a.enabled}`)
      }
    }.padding({ left: 16, right: 16 })
  }
}

@ComponentV2
export struct QuickMessagesSettings {
  @Local list: QuickMessage[] = []
  @Local editing: QuickMessage | null = null
  @Local title: string = ''
  @Local content: string = ''
  @Local show: boolean = false

  aboutToAppear(): void {
    this.load()
  }

  async load(): Promise<void> {
    this.list = await app.api!.quickMessages()
  }

  async save(): Promise<void> {
    try {
      if (this.editing !== null) {
        await app.api!.updateQuickMessage(this.editing.id, this.title, this.content)
      } else {
        await app.api!.createQuickMessage(this.title, this.content)
      }
      this.show = false
      this.load()
    } catch (e) {
      toast(errorText(e))
    }
  }

  @Builder
  editor() {
    Column({ space: 10 }) {
      TextInput({ text: this.title, placeholder: L('Title', '标题') }).height(44).backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.title = v
        })
      TextArea({ text: this.content, placeholder: L('Message', '内容') }).height(140)
        .backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.content = v
        })
      Button(L('Save', '保存')).type(ButtonType.Capsule).height(44).width('100%').backgroundColor($r('app.color.accent'))
        .onClick(() => {
          this.save()
        })
    }.padding(20).width('100%')
  }

  build() {
    Column() {
      SectionHeader({ title: L('Quick messages', '快捷消息'), trailing: L('Add', '添加'), onTrailing: () => {
        this.editing = null
        this.title = ''
        this.content = ''
        this.show = true
      } })
      Column() {
        Card() {
          if (this.list.length === 0) {
            Text(L('None yet', '暂无')).fontSize(14).fontColor($r('app.color.text3')).padding(16)
          }
          ForEach(this.list, (q: QuickMessage, i: number) => {
            if (i > 0) {
              Divider1({})
            }
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(q.title).fontSize(15).fontColor($r('app.color.text'))
                Text(q.content).fontSize(12).fontColor($r('app.color.text3')).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              IconButton({ icon: 'trash', sz: 16, box: 32, color: $r('app.color.danger'), onTap: async () => {
                try {
                  await app.api!.deleteQuickMessage(q.id)
                  this.load()
                } catch (e) {
                  toast(errorText(e))
                }
              } })
            }
            .padding({ left: 16, right: 8, top: 10, bottom: 10 }).width('100%')
            .onClick(() => {
              this.editing = q
              this.title = q.title
              this.content = q.content
              this.show = true
            })
          }, (q: QuickMessage) => `${q.id}-${q.title}`)
        }
      }.padding({ left: 16, right: 16 })
    }
    .bindSheet($$this.show, this.editor(), { height: 340, dragBar: true })
  }
}

@ComponentV2
export struct BarkSettings {
  @Local barkOn: boolean = false
  @Local pushUrl: string = ''
  @Local preview: boolean = true
  @Local loaded: boolean = false
  @Local error: string = ''

  async aboutToAppear(): Promise<void> {
    try {
      const s = await app.api!.barkSettings()
      const o: JObj = s['settings'] !== undefined ? (s['settings'] as JObj) : s
      this.barkOn = bool(o, 'enabled')
      this.pushUrl = str(o, 'push_url', str(o, 'pushUrl'))
      this.preview = bool(o, 'include_preview', bool(o, 'includePreview', true))
      this.loaded = true
    } catch (e) {
      this.error = errorText(e)
    }
  }

  async save(): Promise<void> {
    const s: JObj = {
      'enabled': this.barkOn, 'pushUrl': this.pushUrl.trim(), 'includePreview': this.preview,
      'language': isZh() ? 'zh-Hans' : 'en', 'sourceName': 'HarmonyOS',
      'serverUrl': app.active?.url ?? ''
    } as JObj
    try {
      await app.api!.setBarkSettings(s)
      toast(L('Saved', '已保存'))
    } catch (e) {
      toast(errorText(e))
    }
  }

  build() {
    Column() {
      SectionHeader({ title: L('Bark notifications', 'Bark 通知') })
      Column() {
        Card() {
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor($r('app.color.text3')).padding(16)
          } else {
            Row() {
              Text(L('Notify when a turn finishes', '回合结束时通知')).fontSize(15).fontColor($r('app.color.text'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.barkOn }).selectedColor($r('app.color.accent'))
                .onChange((v: boolean) => {
                  this.barkOn = v
                })
            }.padding({ left: 16, right: 12, top: 10, bottom: 10 })
            Divider1({})
            TextInput({ text: this.pushUrl, placeholder: 'https://api.day.app/<key>' }).type(InputType.Password)
              .height(44).margin({ left: 12, right: 12, top: 8, bottom: 8 }).backgroundColor($r('app.color.surface2'))
              .onChange((v: string) => {
                this.pushUrl = v
              })
            Divider1({})
            Row() {
              Text(L('Include message preview', '包含消息预览')).fontSize(15).fontColor($r('app.color.text'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.preview }).selectedColor($r('app.color.accent'))
                .onChange((v: boolean) => {
                  this.preview = v
                })
            }.padding({ left: 16, right: 12, top: 10, bottom: 10 })
            Row({ space: 10 }) {
              Button(L('Test', '测试')).type(ButtonType.Capsule).height(38).layoutWeight(1)
                .fontColor($r('app.color.accent')).backgroundColor($r('app.color.accent_soft'))
                .onClick(async () => {
                  try {
                    await app.api!.testBark()
                    toast(L('Test sent', '已发送测试'))
                  } catch (e) {
                    toast(errorText(e))
                  }
                })
              Button(L('Save', '保存')).type(ButtonType.Capsule).height(38).layoutWeight(1)
                .backgroundColor($r('app.color.accent'))
                .onClick(() => {
                  this.save()
                })
            }.padding(12)
          }
        }
      }.padding({ left: 16, right: 16 })
    }
  }
}

@ComponentV2
export struct SettingsView {
  @Local editing: string = ''
  @Local showEditor: boolean = false
  @Local page: string = ''
  @Event onLanguage: () => void = () => {
  }

  @Builder
  editorSheet() {
    ServerEditor({ editId: this.editing, onDone: () => {
      this.showEditor = false
    } })
  }

  @Builder
  themeChip(v: string, label: string) {
    Text(label).fontSize(13).padding({ left: 14, right: 14, top: 7, bottom: 7 }).borderRadius(16)
      .fontColor(app.theme === v ? Color.White : $r('app.color.text2'))
      .backgroundColor(app.theme === v ? $r('app.color.accent') : $r('app.color.surface2'))
      .onClick(() => app.setTheme(v))
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        if (this.page.length > 0) {
          IconButton({ icon: 'chevron_left', sz: 22, color: $r('app.color.text'), onTap: () => {
            this.page = ''
          } })
        }
        Text(this.page === 'agents' ? L('Agents', '智能体') : L('Settings', '设置')).fontSize(26)
          .fontWeight(FontWeight.Bold).fontColor($r('app.color.text')).layoutWeight(1)
      }.padding({ left: this.page.length > 0 ? 6 : 20, right: 10, top: 10, bottom: 6 }).width('100%')

      Scroll() {
        Column() {
          if (this.page === 'agents') {
            AgentsSettings()
          } else {
            ServerList({
              onEdit: (id: string) => {
                this.editing = id
                this.showEditor = true
              }, onAdd: () => {
                this.editing = ''
                this.showEditor = true
              }
            })

            SectionHeader({ title: L('Appearance', '外观') })
            Column() {
              Card() {
                Row({ space: 8 }) {
                  this.themeChip('system', L('System', '跟随系统'))
                  this.themeChip('light', L('Light', '浅色'))
                  this.themeChip('dark', L('Dark', '深色'))
                }.padding(12).width('100%')
                Divider1({})
                Row() {
                  Text(L('Language', '语言')).fontSize(15).fontColor($r('app.color.text')).layoutWeight(1)
                  Text('English').fontSize(13).padding({ left: 12, right: 12, top: 6, bottom: 6 }).borderRadius(14)
                    .fontColor(!isZh() ? Color.White : $r('app.color.text2'))
                    .backgroundColor(!isZh() ? $r('app.color.accent') : $r('app.color.surface2'))
                    .onClick(() => {
                      setZh(false)
                      AppPrefs.set('lang', 'en')
                      this.onLanguage()
                    })
                  Text('简体中文').fontSize(13).padding({ left: 12, right: 12, top: 6, bottom: 6 }).borderRadius(14)
                    .margin({ left: 6 })
                    .fontColor(isZh() ? Color.White : $r('app.color.text2'))
                    .backgroundColor(isZh() ? $r('app.color.accent') : $r('app.color.surface2'))
                    .onClick(() => {
                      setZh(true)
                      AppPrefs.set('lang', 'zh')
                      this.onLanguage()
                    })
                }.padding({ left: 16, right: 12, top: 10, bottom: 10 })
              }
            }.padding({ left: 16, right: 16 })

            if (app.api !== null) {
              SectionHeader({ title: L('AI & Agents', 'AI 与智能体') })
              Column() {
                Card() {
                  NavRow({ icon: 'person_2', title: L('Agents', '智能体'),
                    value: `${app.enabledAgents.length}/${app.agents.length}`, onTap: () => {
                      this.page = 'agents'
                    } })
                }
              }.padding({ left: 16, right: 16 })
              QuickMessagesSettings()
              BarkSettings()
            }

            SectionHeader({ title: L('About', '关于') })
            Column() {
              Card() {
                NavRow({ icon: 'info_circle', title: 'Codeg for HarmonyOS', value: '1.0.0', chevron: false })
                Divider1({ inset: 58 })
                NavRow({ icon: 'computer', title: L('Server version', '服务器版本'),
                  value: app.health?.version ?? '—', chevron: false })
              }
            }.padding({ left: 16, right: 16 })
          }
          Column().height(100)
        }
      }.layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .bindSheet($$this.showEditor, this.editorSheet(), { height: SheetSize.LARGE, dragBar: true })
  }
}
