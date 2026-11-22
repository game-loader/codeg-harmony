import { common } from '@kit.AbilityKit'
import { Draft, PendingImage, SessionController } from '../session/SessionController'
import { cleanupUpload, pickFiles, pickImages } from '../session/Attachments'
import { UploadedAttachment } from '../net/Api'
import { UploadFile } from '../net/CodegClient'
import { errorText } from '../net/ApiError'
import { AgentInfo, ExpertSkill, QuickMessage } from '../model/Models'
import { AgentOptions } from '../session/Interactive'
import { agentCatalog } from '../session/AgentOptionsModel'
import { AgentOptionsPanel } from './AgentOptionsPanel'
import { app } from '../store/AppState'
import { L, langCode, formatTokens } from '../common/I18n'
import { sym, toast } from './Common'
import { agentName } from '../common/Agents'
import {
  MAX_PER_KIND, REF_KINDS, RefBus, RefItem, RefKind, agentRef, commitRef, expandRefs, listAssistants, matches,
  mentionAt, MentionAt, refKindLabel, searchFiles, sessionRef
} from '../session/References'
import { ConversationSummary, GitLogEntry } from '../model/Models'
import { AgentAvatar } from './Common'

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
  // `@` references (web: composer/suggestion). Tokens like `@Title` stay visible in
  // the draft and become `[Title](codeg://session/42)` when sent.
  @Local refs: RefItem[] = []
  @Local mention: MentionAt = new MentionAt()
  @Local refTab: RefKind = RefKind.Session
  @Local fileHits: RefItem[] = []
  @Local filesLoading: boolean = false
  @Local assistants: RefItem[] = []
  @Local commits: RefItem[] = []
  private caret: number = 0
  private areaCtl: TextAreaController = new TextAreaController()
  private fileTimer: number = -1
  private fileQuery: string = '\u0000'
  private assistantsLoaded: boolean = false
  private commitsFor: string = ''
  private busHandler: (r: RefItem) => void = (r: RefItem) => {
    this.insertRef(r, -1)
  }

  aboutToAppear(): void {
    RefBus.on(this.busHandler)
  }

  aboutToDisappear(): void {
    RefBus.off(this.busHandler)
  }

  get folderRoot(): string {
    const f = this.ctrl?.folder ?? null
    return f !== null && !f.isChat ? f.path : ''
  }

  get mentionOpen(): boolean {
    return this.mention.start >= 0
  }

  kindsShown(): RefKind[] {
    return REF_KINDS.filter((k: RefKind) => {
      if (k === RefKind.File || k === RefKind.Commit) {
        return this.folderRoot.length > 0
      }
      if (k === RefKind.Assistant) {
        return this.assistants.length > 0
      }
      return true
    })
  }

  candidates(): RefItem[] {
    const q = this.mention.query
    let list: RefItem[] = []
    if (this.refTab === RefKind.Session) {
      list = app.conversations.slice()
        .sort((a: ConversationSummary, b: ConversationSummary) => b.updatedAt - a.updatedAt)
        .map((c: ConversationSummary) => sessionRef(c))
    } else if (this.refTab === RefKind.Agent) {
      list = app.enabledAgents.map((a: AgentInfo) => agentRef(a.agentType, a.name, a.description))
    } else if (this.refTab === RefKind.Assistant) {
      list = this.assistants
    } else if (this.refTab === RefKind.File) {
      return this.fileHits.slice(0, MAX_PER_KIND)
    } else {
      list = this.commits
    }
    return list.filter((r: RefItem) => matches(r, q)).slice(0, MAX_PER_KIND)
  }

  /** Called on every edit / caret move: opens, updates or closes the `@` panel. */
  updateMention(): void {
    let caret = this.text.length
    try {
      caret = this.areaCtl.getCaretOffset().index
    } catch (e) {
      // Not attached yet.
    }
    this.caret = caret
    const m = mentionAt(this.text, caret)
    const opening = m.start >= 0 && this.mention.start < 0
    this.mention = m
    if (m.start < 0) {
      return
    }
    if (opening) {
      this.loadLazy()
    }
    this.scheduleFileSearch()
  }

  loadLazy(): void {
    const api = app.api
    if (api === null) {
      return
    }
    if (!this.assistantsLoaded) {
      this.assistantsLoaded = true
      listAssistants(api).then((a: RefItem[]) => {
        this.assistants = a
      })
    }
    const root = this.folderRoot
    if (root.length > 0 && this.commitsFor !== root) {
      this.commitsFor = root
      api.gitLog(root, 200).then((log: GitLogEntry[]) => {
        this.commits = log.map((e: GitLogEntry) => commitRef(root, e))
      }).catch(() => {
        this.commits = []
      })
    }
  }

  scheduleFileSearch(): void {
    const root = this.folderRoot
    const api = app.api
    if (root.length === 0 || api === null || this.refTab !== RefKind.File || this.fileQuery === this.mention.query) {
      return
    }
    clearTimeout(this.fileTimer)
    const q = this.mention.query
    this.fileTimer = setTimeout((): void => {
      this.fileQuery = q
      this.filesLoading = true
      searchFiles(api, root, q).then((hits: RefItem[]) => {
        if (q === this.mention.query) {
          this.fileHits = hits
        }
      }).catch(() => {
        this.fileHits = []
      }).finally(() => {
        this.filesLoading = false
      })
    }, 180)
  }

  /** Replaces `@query` (or inserts at the caret when start < 0) with the ref's token. */
  insertRef(r: RefItem, start: number): void {
    const from = start >= 0 ? start : Math.min(this.caret, this.text.length)
    const to = start >= 0 ? Math.min(Math.max(this.caret, start), this.text.length) : from
    const before = this.text.substring(0, from)
    const sep = start < 0 && before.length > 0 && !new RegExp('\\s$').test(before) ? ' ' : ''
    const ins = `${sep}${r.token} `
    this.text = before + ins + this.text.substring(to)
    if (!this.refs.some((x: RefItem) => x.uri === r.uri && x.token === r.token)) {
      this.refs = this.refs.concat([r])
    }
    this.mention = new MentionAt()
    const pos = from + ins.length
    this.caret = pos
    setTimeout((): void => {
      try {
        this.areaCtl.caretPosition(pos)
      } catch (e) {
        // Not attached.
      }
    }, 0)
  }

  @Builder
  mentionPanel() {
    Column() {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.kindsShown(), (k: RefKind) => {
            Text(refKindLabel(k)).fontSize(12.5)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 }).borderRadius(14)
              .fontColor(this.refTab === k ? Color.White : $r('app.color.text2'))
              .backgroundColor(this.refTab === k ? $r('app.color.accent') : $r('app.color.surface2'))
              .onClick(() => {
                this.refTab = k
                this.fileQuery = '\u0000'
                this.scheduleFileSearch()
              })
          }, (k: RefKind) => k)
        }.padding({ left: 10, right: 10, top: 8, bottom: 6 })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

      if (this.refTab === RefKind.File && this.filesLoading && this.fileHits.length === 0) {
        LoadingProgress().width(22).height(22).color($r('app.color.accent')).margin(10)
      } else if (this.candidates().length === 0) {
        Text(L('No matches', '无匹配项')).fontSize(13).fontColor($r('app.color.text3')).padding(12)
      } else {
        List() {
          ForEach(this.candidates(), (r: RefItem) => {
            ListItem() {
              Row({ space: 10 }) {
                if (r.agent.length > 0) {
                  AgentAvatar({ agent: r.agent, sz: 26 })
                } else {
                  SymbolGlyph(sym(r.kind === RefKind.File ? 'doc' : 'rectangle_split_3x1')).fontSize(18)
                    .fontColor([$r('app.color.accent')]).width(26)
                }
                Column({ space: 1 }) {
                  Text(r.label).fontSize(14.5).fontColor($r('app.color.text')).maxLines(1)
                    .fontFamily(r.kind === RefKind.Commit ? 'monospace' : 'HarmonyOS Sans')
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (r.detail.length > 0) {
                    Text(r.detail).fontSize(11.5).fontColor($r('app.color.text3')).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .width('100%')
              .onClick(() => this.insertRef(r, this.mention.start))
            }
          }, (r: RefItem) => `${r.kind}-${r.uri}`)
        }
        .constraintSize({ maxHeight: 260 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .border({ width: { bottom: 0.5 }, color: $r('app.color.border') })
  }

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
    const raw = this.text
    const rawRefs = this.refs
    const d = new Draft()
    d.text = expandRefs(raw, rawRefs)
    d.images = this.images
    d.files = this.files
    this.text = ''
    this.refs = []
    this.mention = new MentionAt()
    this.images = []
    this.files = []
    this.sending = true
    const ok = await c.send(d)
    this.sending = false
    if (!ok) {
      this.text = raw
      this.refs = rawRefs
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
    // Slash commands: the running session's own list, else the agent's catalog.
    let known: AgentOptions | null = c.opts.options
    if (known === null || known.commands.length === 0) {
      try {
        known = await agentCatalog(api, c.agentType, c.folder?.path)
      } catch (e) {
        // The list is optional.
      }
    }
    for (const cmd of known?.commands ?? []) {
      if (expertIds.has(cmd)) {
        continue
      }
      const it = new InsertItem()
      it.kind = 'slash'
      it.title = `/${cmd}`
      it.subtitle = known?.commandDescriptions.get(cmd) ?? ''
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
      it.value = a.agentType
      items.push(it)
    }
    this.insertItems = items
    this.insertLoading = false
  }

  applyInsert(it: InsertItem): void {
    if (it.kind === 'agent') {
      const a = app.enabledAgents.find((x: AgentInfo) => x.agentType === it.value)
      if (a !== undefined) {
        this.insertRef(agentRef(a.agentType, a.name, a.description), -1)
      }
    } else if (it.kind === 'slash' || it.kind === 'expert') {
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
    AgentOptionsPanel({ ctrl: this.ctrl })
  }

  /** "Model · Mode" of the session, once known. */
  modelLabel(): string {
    return this.ctrl?.opts.options?.summary ?? ''
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
        if (this.mentionOpen) {
          this.mentionPanel()
        }
        TextArea({ text: this.text, controller: this.areaCtl, placeholder: this.ctrl !== null && this.ctrl.running ?
          L('Steer the running turn…', '引导当前回合…') : L('Message the agent…', '给智能体发消息…') })
          .fontSize(15.5)
          .backgroundColor(Color.Transparent)
          .constraintSize({ minHeight: 44, maxHeight: this.compact ? 120 : 220 })
          .padding({ left: 14, right: 14, top: 10, bottom: 4 })
          .enterKeyType(EnterKeyType.NEW_LINE)
          .onChange((v: string) => {
            this.text = v
            // Drop refs whose token was edited away.
            if (this.refs.some((r: RefItem) => !v.includes(r.token))) {
              this.refs = this.refs.filter((r: RefItem) => v.includes(r.token))
            }
            this.updateMention()
          })
          .onTextSelectionChange((start: number, end: number) => {
            if (start === end && start !== this.caret) {
              this.updateMention()
            }
          })

        Row({ space: 4 }) {
          Button({ type: ButtonType.Circle }) {
            Text('@').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text2'))
          }
          .width(36).height(36).backgroundColor($r('app.color.surface2'))
          .onClick(() => {
            // Same as typing `@` at the caret.
            const at = Math.min(this.caret, this.text.length)
            const before = this.text.substring(0, at)
            const lead = before.length > 0 && !new RegExp('\\s$').test(before) ? ' @' : '@'
            this.text = before + lead + this.text.substring(at)
            const pos = at + lead.length
            this.caret = pos
            this.mention = mentionAt(this.text, pos)
            this.loadLazy()
            setTimeout((): void => {
              try {
                this.areaCtl.caretPosition(pos)
              } catch (e) {
                // Not attached.
              }
            }, 0)
          })
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

          // The options button takes the free width and shortens its label to
          // fit, so a long model name cannot push the send button off screen.
          Row() {
            Row({ space: 4 }) {
              Text(agentName(this.ctrl?.agentType ?? '')).fontSize(12).fontColor($r('app.color.text2')).maxLines(1)
              if (this.modelLabel().length > 0) {
                Text(`· ${this.modelLabel()}`).fontSize(12).fontColor($r('app.color.text3')).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
              }
              SymbolGlyph(sym('chevron_down')).fontSize(11).fontColor([$r('app.color.text3')])
            }
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .constraintSize({ maxWidth: '100%' })
            .borderRadius(16)
            .clip(true)
            .backgroundColor($r('app.color.surface2'))
            .onClick(() => {
              this.showOptions = true
              this.ctrl?.loadOptions()
            })
            .bindSheet($$this.showOptions, this.optionsSheet(), {
              detents: [SheetSize.MEDIUM, SheetSize.LARGE], dragBar: true, preferType: SheetType.CENTER,
              backgroundColor: $r('app.color.surface')
            })
          }
          .layoutWeight(1)

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
