import { common } from '@kit.AbilityKit'
import { Draft, PendingImage, SessionController } from '../session/SessionController'
import { cleanupUpload, pickFiles, pickImages, agentMention } from '../session/Attachments'
import { UploadedAttachment } from '../net/Api'
import { UploadFile } from '../net/CodegClient'
import { errorText } from '../net/ApiError'
import { AgentInfo, ExpertSkill, QuickMessage } from '../model/Models'
import { ConfigChoice, ConfigOption, ModeOption } from '../session/Interactive'
import { app } from '../store/AppState'
import { L, langCode, formatTokens } from '../common/I18n'
import { sym, toast } from './Common'
import { agentName } from '../common/Agents'

class InsertItem {
  kind: string = ''
  title: string = ''
  subtitle: string = ''
  value: string = ''
}

@ComponentV2
export struct Composer {
  @Param ctrl: SessionController | null = null
  @Param compact: boolean = false
  @Local text: string = ''
  @Local images: PendingImage[] = []
  @Local files: UploadedAttachment[] = []
  @Local uploading: number = 0
  @Local showInsert: boolean = false
  @Local insertItems: InsertItem[] = []
  @Local insertLoading: boolean = false
  @Local showOptions: boolean = false
  @Local sending: boolean = false

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext
  }

  canSend(): boolean {
    return !this.sending && this.uploading === 0 &&
      (this.text.trim().length > 0 || this.images.length > 0 || this.files.length > 0)
  }

  async doSend(): Promise<void> {
    const c = this.ctrl
    if (c === null || !this.canSend()) {
      return
    }
    const d = new Draft()
    d.text = this.text
    d.images = this.images
    d.files = this.files
    this.text = ''
    this.images = []
    this.files = []
    this.sending = true
    const ok = await c.send(d)
    this.sending = false
    if (!ok) {
      this.text = d.text
      this.images = d.images
      this.files = d.files
    }
  }

  async addPhotos(): Promise<void> {
    try {
      const picked = await pickImages(6)
      this.images = this.images.concat(picked)
    } catch (e) {
      toast(errorText(e))
    }
  }

  async addFiles(): Promise<void> {
    const api = app.api
    if (api === null) {
      return
    }
    let picked: UploadFile[] = []
    try {
      picked = await pickFiles(this.ctx(), 5)
    } catch (e) {
      toast(errorText(e))
      return
    }
    for (const f of picked) {
      this.uploading++
      try {
        const u = await api.uploadAttachment(f)
        this.files = this.files.concat([u])
      } catch (e) {
        toast(`${f.name}: ${errorText(e)}`)
      } finally {
        this.uploading--
        cleanupUpload(f)
      }
    }
  }

  async openInsert(): Promise<void> {
    const c = this.ctrl
    const api = app.api
    if (c === null || api === null) {
      return
    }
    this.showInsert = true
    this.insertLoading = true
    const items: InsertItem[] = []
    const results = await Promise.all([api.quickMessages(), api.experts(c.agentType, langCode())])
    for (const q of results[0] as QuickMessage[]) {
      const it = new InsertItem()
      it.kind = 'quick'
      it.title = q.title
      it.subtitle = q.content
      it.value = q.content
      items.push(it)
    }
    const experts = results[1] as ExpertSkill[]
    const expertIds = new Set<string>(experts.map((e: ExpertSkill) => e.id))
    for (const e of experts) {
      const it = new InsertItem()
      it.kind = 'expert'
      it.title = e.name
      it.subtitle = e.description
      it.value = `${c.agentType === 'codex' ? '$' : '/'}${e.id} `
      items.push(it)
    }
    if (c.options === null) {
      await c.loadOptions()
    }
    for (const cmd of c.options?.commands ?? []) {
      if (expertIds.has(cmd)) {
        continue
      }
      const it = new InsertItem()
      it.kind = 'slash'
      it.title = `/${cmd}`
      it.subtitle = c.options?.commandDescriptions.get(cmd) ?? ''
      it.value = `/${cmd} `
      items.push(it)
    }
    for (const a of app.enabledAgents) {
      if (a.agentType === c.agentType) {
        continue
      }
      const it = new InsertItem()
      it.kind = 'agent'
      it.title = L(`Delegate to ${a.name}`, `委托给 ${a.name}`)
      it.subtitle = a.description
      it.value = agentMention(a.name, a.agentType)
      if (it.value.length > 0) {
        items.push(it)
      }
    }
    this.insertItems = items
    this.insertLoading = false
  }

  applyInsert(it: InsertItem): void {
    if (it.kind === 'slash' || it.kind === 'expert') {
      this.text = it.value + this.text
    } else {
      const sep = this.text.length > 0 && !this.text.endsWith(' ') && !this.text.endsWith('\n') ? ' ' : ''
      this.text = this.text + sep + it.value + (it.kind === 'agent' ? ' ' : '')
    }
    this.showInsert = false
  }

  @Builder
  insertSheet() {
    Column() {
      Row() {
        Text(L('Insert', '插入')).fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1)
          .fontColor($r('app.color.text'))
        Row({ space: 14 }) {
          Column({ space: 4 }) {
            SymbolGlyph(sym('picture')).fontSize(22).fontColor([$r('app.color.accent')])
            Text(L('Photos', '照片')).fontSize(11).fontColor($r('app.color.text2'))
          }.onClick(() => {
            this.showInsert = false
            this.addPhotos()
          })
          Column({ space: 4 }) {
            SymbolGlyph(sym('paperclip')).fontSize(22).fontColor([$r('app.color.accent')])
            Text(L('Files', '文件')).fontSize(11).fontColor($r('app.color.text2'))
          }.onClick(() => {
            this.showInsert = false
            this.addFiles()
          })
        }
      }.width('100%').padding({ left: 20, right: 20, top: 8, bottom: 12 })

      if (this.insertLoading) {
        LoadingProgress().width(28).height(28).color($r('app.color.accent')).margin(24)
      } else if (this.insertItems.length === 0) {
        Text(L('No quick messages, skills or commands', '没有快捷消息、技能或命令')).fontSize(14)
          .fontColor($r('app.color.text3')).margin(24)
      } else {
        List() {
          ForEach(this.insertItems, (it: InsertItem) => {
            ListItem() {
              Row({ space: 12 }) {
                SymbolGlyph(sym(it.kind === 'quick' ? 'bolt' : it.kind === 'expert' ? 'star' :
                  it.kind === 'agent' ? 'person_2' : 'chevron_right'))
                  .fontSize(18).fontColor([$r('app.color.accent')])
                Column({ space: 2 }) {
                  Text(it.title).fontSize(15).fontColor($r('app.color.text')).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (it.subtitle.length > 0) {
                    Text(it.subtitle).fontSize(12).fontColor($r('app.color.text3')).maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }
              .padding({ left: 20, right: 20, top: 10, bottom: 10 })
              .width('100%')
              .onClick(() => this.applyInsert(it))
            }
          }, (it: InsertItem, i: number) => `${i}-${it.kind}-${it.title}`)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: $r('app.color.border'), startMargin: 50 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  optionsSheet() {
    Scroll() {
      Column({ space: 14 }) {
        Text(L('Session options', '会话选项')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        if (this.ctrl === null || this.ctrl.options === null) {
          LoadingProgress().width(28).height(28).color($r('app.color.accent'))
        } else {
          if (this.ctrl.options.modes.length > 0) {
            Text(L('Mode', '模式')).fontSize(12).fontColor($r('app.color.text3'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.ctrl.options.modes, (m: ModeOption) => {
                Text(m.name).fontSize(14).padding({ left: 14, right: 14, top: 8, bottom: 8 })
                  .margin({ right: 8, bottom: 8 }).borderRadius(18)
                  .fontColor(this.ctrl?.options?.currentMode === m.id ? Color.White : $r('app.color.text'))
                  .backgroundColor(this.ctrl?.options?.currentMode === m.id ? $r('app.color.accent') :
                  $r('app.color.surface2'))
                  .onClick(() => {
                    this.ctrl?.setMode(m.id)
                  })
              }, (m: ModeOption) => m.id)
            }
          }
          ForEach(this.ctrl.options.configs.filter((c: ConfigOption) => c.type === 'select'), (c: ConfigOption) => {
            Column({ space: 8 }) {
              Text(c.name).fontSize(12).fontColor($r('app.color.text3'))
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(c.choices, (ch: ConfigChoice) => {
                  Text(ch.name).fontSize(14).padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .margin({ right: 8, bottom: 8 }).borderRadius(18)
                    .fontColor(c.current === ch.value ? Color.White : $r('app.color.text'))
                    .backgroundColor(c.current === ch.value ? $r('app.color.accent') : $r('app.color.surface2'))
                    .onClick(() => {
                      this.ctrl?.setConfig(c.id, ch.value)
                    })
                }, (ch: ConfigChoice) => ch.value)
              }
            }.alignItems(HorizontalAlign.Start).width('100%')
          }, (c: ConfigOption) => `${c.id}-${c.current}`)
          if (this.ctrl.options.modes.length === 0 && this.ctrl.options.configs.length === 0) {
            Text(L('This agent has no selectable options', '该智能体没有可选项')).fontSize(14)
              .fontColor($r('app.color.text3'))
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(20)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .backgroundColor($r('app.color.surface'))
  }

  modelLabel(): string {
    const o = this.ctrl?.options
    if (o === null || o === undefined) {
      return ''
    }
    const model = o.configs.find((c: ConfigOption) => c.id.includes('model') || c.name.toLowerCase().includes('model'))
    if (model !== undefined) {
      const ch = model.choices.find((x: ConfigChoice) => x.value === model.current)
      return ch?.name ?? model.current
    }
    const m = o.modes.find((x: ModeOption) => x.id === o.currentMode)
    return m?.name ?? ''
  }

  build() {
    Column({ space: 6 }) {
      if (this.ctrl !== null && this.ctrl.queued.length > 0) {
        Column({ space: 4 }) {
          ForEach(this.ctrl.queued, (q: string, i: number) => {
            Row({ space: 8 }) {
              SymbolGlyph(sym('clock')).fontSize(13).fontColor([$r('app.color.text3')])
              Text(q).fontSize(13).fontColor($r('app.color.text2')).maxLines(1).layoutWeight(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              SymbolGlyph(sym('xmark')).fontSize(13).fontColor([$r('app.color.text3')])
                .onClick(() => this.ctrl?.removeQueued(i))
            }.width('100%')
          }, (q: string, i: number) => `${i}-${q}`)
        }
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(12)
        .backgroundColor($r('app.color.surface2'))
      }

      if (this.images.length > 0 || this.files.length > 0 || this.uploading > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.images, (im: PendingImage, i: number) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(`data:${im.mimeType};base64,${im.data}`).width(56).height(56).borderRadius(10)
                  .objectFit(ImageFit.Cover)
                SymbolGlyph(sym('xmark_circle_fill')).fontSize(18).fontColor([$r('app.color.text2')])
                  .onClick(() => {
                    this.images = this.images.filter((_: PendingImage, j: number) => j !== i)
                  })
              }
            }, (im: PendingImage, i: number) => `img-${i}-${im.data.length}`)
            ForEach(this.files, (f: UploadedAttachment, i: number) => {
              Row({ space: 6 }) {
                SymbolGlyph(sym('doc')).fontSize(14).fontColor([$r('app.color.accent')])
                Text(f.name).fontSize(12).fontColor($r('app.color.text')).maxLines(1)
                  .constraintSize({ maxWidth: 140 }).textOverflow({ overflow: TextOverflow.Ellipsis })
                SymbolGlyph(sym('xmark')).fontSize(12).fontColor([$r('app.color.text3')])
                  .onClick(() => {
                    this.files = this.files.filter((_: UploadedAttachment, j: number) => j !== i)
                  })
              }
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .borderRadius(10)
              .backgroundColor($r('app.color.surface2'))
            }, (f: UploadedAttachment, i: number) => `file-${i}-${f.path}`)
            if (this.uploading > 0) {
              Row({ space: 6 }) {
                LoadingProgress().width(16).height(16).color($r('app.color.accent'))
                Text(L('Uploading…', '上传中…')).fontSize(12).fontColor($r('app.color.text3'))
              }.padding(8)
            }
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }

      Column() {
        TextArea({ text: this.text, placeholder: this.ctrl !== null && this.ctrl.running ?
          L('Steer the running turn…', '引导当前回合…') : L('Message the agent…', '给智能体发消息…') })
          .fontSize(15.5)
          .backgroundColor(Color.Transparent)
          .constraintSize({ minHeight: 44, maxHeight: this.compact ? 120 : 220 })
          .padding({ left: 14, right: 14, top: 10, bottom: 4 })
          .enterKeyType(EnterKeyType.NEW_LINE)
          .onChange((v: string) => {
            this.text = v
          })

        Row({ space: 4 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(sym('plus')).fontSize(19).fontColor([$r('app.color.text2')])
          }
          .width(36).height(36).backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            this.openInsert()
          })
          .bindSheet($$this.showInsert, this.insertSheet(), {
            height: SheetSize.MEDIUM, dragBar: true, showClose: false,
            preferType: SheetType.CENTER, backgroundColor: $r('app.color.surface')
          })

          Row({ space: 4 }) {
            Text(agentName(this.ctrl?.agentType ?? '')).fontSize(12).fontColor($r('app.color.text2')).maxLines(1)
            if (this.modelLabel().length > 0) {
              Text(`· ${this.modelLabel()}`).fontSize(12).fontColor($r('app.color.text3')).maxLines(1)
                .constraintSize({ maxWidth: 140 }).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            SymbolGlyph(sym('chevron_down')).fontSize(11).fontColor([$r('app.color.text3')])
          }
          .padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            this.showOptions = true
            if (this.ctrl !== null && this.ctrl.options === null) {
              this.ctrl.loadOptions()
            }
          })
          .bindSheet($$this.showOptions, this.optionsSheet(), {
            height: SheetSize.MEDIUM, dragBar: true, preferType: SheetType.CENTER,
            backgroundColor: $r('app.color.surface')
          })

          Blank()

          if (this.ctrl !== null && this.ctrl.contextSize > 0) {
            Text(`${formatTokens(this.ctrl.usedTokens)}/${formatTokens(this.ctrl.contextSize)}`)
              .fontSize(11).fontColor($r('app.color.text3')).fontFamily('monospace').margin({ right: 4 })
          }

          if (this.ctrl !== null && this.ctrl.running && !this.canSend()) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph(sym('stop_circle_fill')).fontSize(34).fontColor([$r('app.color.danger')])
            }
            .width(38).height(38).backgroundColor(Color.Transparent)
            .onClick(() => {
              this.ctrl?.cancel()
            })
          } else {
            Button({ type: ButtonType.Circle }) {
              if (this.sending) {
                LoadingProgress().width(22).height(22).color(Color.White)
              } else {
                SymbolGlyph(sym('arrow_up')).fontSize(19).fontColor([Color.White])
              }
            }
            .width(38).height(38)
            .backgroundColor(this.canSend() ? $r('app.color.accent') : $r('app.color.surface3'))
            .enabled(this.canSend())
            .onClick(() => {
              this.doSend()
            })
          }
        }
        .padding({ left: 8, right: 8, bottom: 8 })
        .width('100%')
      }
      .width('100%')
      .borderRadius(24)
      .backgroundColor($r('app.color.surface'))
      .border({ width: 0.5, color: $r('app.color.border') })
      .shadow({ radius: 20, color: '#14000000', offsetY: 2 })
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 8 })
    .width('100%')
  }
}
