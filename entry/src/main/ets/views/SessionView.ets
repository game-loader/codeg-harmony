import { Api } from '../net/Api'
import { SessionController } from '../session/SessionController'
import { ItemKind, TItem, ImageRef, splitUserResources, UserText } from '../session/Transcript'
import { SessionFailure } from '../session/Interactive'
import { MarkdownView, copyText } from '../components/Markdown'
import { ToolCard, PlanList } from '../components/ToolCard'
import { PermissionCard, PlanApprovalCard, QuestionCard } from '../components/InteractiveCards'
import { Composer } from '../components/Composer'
import { AgentAvatar, Banner, Loading, StatusPill, sym, IconButton } from '../components/Common'
import { layout } from '../store/Layout'
import { app } from '../store/AppState'
import { L, relativeTime } from '../common/I18n'
import { agentName, STATUSES, statusLabel } from '../common/Agents'

@ComponentV2
export struct ThinkingBlock {
  @Param text: string = ''
  @Param live: boolean = false
  @Local open: boolean = false

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        SymbolGlyph(sym('lightbulb')).fontSize(13).fontColor([$r('app.color.text3')])
        Text(this.live ? L('Thinking…', '思考中…') : L('Thought', '思考过程')).fontSize(13)
          .fontColor($r('app.color.text3'))
        SymbolGlyph(sym(this.open ? 'chevron_up' : 'chevron_down')).fontSize(11).fontColor([$r('app.color.text3')])
      }.onClick(() => {
        this.open = !this.open
      })
      if (this.open || this.live) {
        Text(this.live && !this.open && this.text.length > 280 ? '…' + this.text.substring(this.text.length - 280) :
        this.text)
          .fontSize(13).lineHeight(20).fontColor($r('app.color.text3')).fontStyle(FontStyle.Italic)
          .copyOption(CopyOptions.LocalDevice).maxLines(this.open ? 100000 : 4)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, top: 2, bottom: 2 })
    .border({ width: { left: 2 }, color: $r('app.color.border') })
    .width('100%')
  }
}

@ComponentV2
export struct UserBubble {
  @Param item: TItem = new TItem('', ItemKind.User)

  @Computed
  get parts(): UserText {
    return splitUserResources(this.item.text)
  }

  build() {
    Column({ space: 6 }) {
      if (this.item.images.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
          ForEach(this.item.images, (im: ImageRef, i: number) => {
            Image(`data:${im.mimeType};base64,${im.data}`).width(120).height(120).borderRadius(14)
              .objectFit(ImageFit.Cover).margin({ left: 6, bottom: 6 })
          }, (im: ImageRef, i: number) => `${i}-${im.data.length}`)
        }
      }
      if (this.parts.files.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End }) {
          ForEach(this.parts.files, (f: string) => {
            Row({ space: 5 }) {
              SymbolGlyph(sym('paperclip')).fontSize(12).fontColor([$r('app.color.accent')])
              Text(f).fontSize(12).fontColor($r('app.color.text2')).maxLines(1)
                .constraintSize({ maxWidth: 180 }).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .margin({ left: 6, bottom: 4 })
            .borderRadius(12)
            .backgroundColor($r('app.color.surface2'))
          }, (f: string) => f)
        }
      }
      if (this.parts.text.length > 0) {
        Text(this.parts.text)
          .fontSize(15.5)
          .lineHeight(23)
          .fontColor($r('app.color.user_text'))
          .copyOption(CopyOptions.LocalDevice)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius({ topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 6 })
          .backgroundColor($r('app.color.user_bubble'))
          .opacity(this.item.pending ? 0.7 : 1)
          .constraintSize({ maxWidth: '86%' })
          .bindContextMenu(this.menu(), ResponseType.LongPress)
      }
    }
    .alignItems(HorizontalAlign.End)
    .width('100%')
  }

  @Builder
  menu() {
    Menu() {
      MenuItem({ content: L('Copy', '复制') }).onClick(() => copyText(this.parts.text))
    }
  }
}

@ComponentV2
export struct SessionView {
  @Param ctrl: SessionController | null = null
  @Param showBack: boolean = false
  @Param showDetailsToggle: boolean = false
  @Event onBack: () => void = () => {
  }
  @Event onOpenFiles: () => void = () => {
  }
  @Local stickToBottom: boolean = true
  @Local showMenu: boolean = false
  private scroller: ListScroller = new ListScroller()

  /**
   * The scroller is only bound once the transcript List exists; while the
   * conversation is loading a spinner is shown instead and scrollEdge throws
   * BusinessError 100004, which would crash the app.
   */
  toBottom(): void {
    try {
      this.scroller.scrollEdge(Edge.Bottom)
    } catch (e) {
      // Not bound yet.
    }
  }

  aboutToAppear(): void {
    setTimeout((): void => {
      this.toBottom()
    }, 80)
  }

  rootPath(): string {
    return this.ctrl?.folder?.path ?? ''
  }

  scrollDown(): void {
    if (this.stickToBottom) {
      this.toBottom()
    }
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      if (this.showBack) {
        IconButton({ icon: 'chevron_left', sz: 22, color: $r('app.color.text'), onTap: () => this.onBack() })
      }
      AgentAvatar({ agent: this.ctrl?.agentType ?? '', sz: 30 })
      Column({ space: 1 }) {
        Text(this.ctrl?.title ?? '').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 6 }) {
          Text(agentName(this.ctrl?.agentType ?? '')).fontSize(12).fontColor($r('app.color.text3'))
          if ((this.ctrl?.folder?.name ?? '').length > 0) {
            Text(`· ${this.ctrl?.folder?.displayName ?? ''}`).fontSize(12).fontColor($r('app.color.text3'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.ctrl !== null && this.ctrl.connState === 'reconnecting') {
        Text(L('Reconnecting', '重连中')).fontSize(11).fontColor($r('app.color.warning'))
      }
      if (this.ctrl !== null && this.ctrl.status.length > 0) {
        StatusPill({ status: this.ctrl.status })
      }
      if (this.ctrl !== null && this.ctrl.folder !== null && !this.ctrl.folder.isChat) {
        IconButton({ icon: 'folder', sz: 19, onTap: () => this.onOpenFiles() })
      }
      IconButton({ icon: 'dot_grid_1x2', sz: 19, onTap: () => {
        this.showMenu = true
      } })
        .bindMenu($$this.showMenu, this.sessionMenu())
    }
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .width('100%')
    .backgroundColor($r('app.color.bg'))
  }

  @Builder
  sessionMenu() {
    Menu() {
      MenuItem({ content: L('Refresh', '刷新') }).onClick(() => {
        this.ctrl?.reloadHistory()
      })
      MenuItemGroup({ header: L('Status', '状态') }) {
        ForEach(STATUSES, (s: string) => {
          MenuItem({ content: statusLabel(s) }).selected(this.ctrl?.status === s).onClick(() => {
            const c = this.ctrl
            if (c !== null && c.conversationId > 0) {
              c.status = s
              app.mutateConversation((api: Api): Promise<void> => api.setStatus(c.conversationId, s))
            }
          })
        }, (s: string) => s)
      }
    }
  }

  @Builder
  item(it: TItem) {
    if (it.kind === ItemKind.User) {
      UserBubble({ item: it })
    } else if (it.kind === ItemKind.Text) {
      MarkdownView({ text: it.text, rootPath: this.rootPath() })
        .bindContextMenu(this.textMenu(it.text), ResponseType.LongPress)
    } else if (it.kind === ItemKind.Thinking) {
      ThinkingBlock({ text: it.text, live: it.live })
    } else if (it.kind === ItemKind.Tool && it.tool !== null) {
      ToolCard({ tool: it.tool, rootPath: this.rootPath() })
    } else if (it.kind === ItemKind.Image) {
      Column({ space: 6 }) {
        ForEach(it.images, (im: ImageRef, i: number) => {
          Image(`data:${im.mimeType};base64,${im.data}`).width('100%').borderRadius(14).objectFit(ImageFit.Contain)
            .constraintSize({ maxHeight: 420 })
        }, (im: ImageRef, i: number) => `${i}`)
        if (it.text.length > 0) {
          Text(it.text).fontSize(12).fontColor($r('app.color.text3'))
        }
      }.width('100%')
    } else if (it.kind === ItemKind.Error) {
      Row({ space: 8 }) {
        SymbolGlyph(sym('exclamationmark_triangle')).fontSize(15).fontColor([$r('app.color.danger')])
        Text(it.text).fontSize(13.5).fontColor($r('app.color.danger')).layoutWeight(1)
          .copyOption(CopyOptions.LocalDevice)
      }
      .padding(12).width('100%').borderRadius(12).backgroundColor($r('app.color.danger_soft'))
    } else if (it.kind === ItemKind.Footer) {
      Text(`${it.text}${it.ts > 0 ? ' · ' + relativeTime(it.ts) : ''}`).fontSize(11)
        .fontColor($r('app.color.text3')).margin({ bottom: 6 })
    }
  }

  @Builder
  textMenu(text: string) {
    Menu() {
      MenuItem({ content: L('Copy message', '复制消息') }).onClick(() => copyText(text))
    }
  }

  @Builder
  transcript() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (this.ctrl === null || (this.ctrl.loading && this.ctrl.items.length === 0)) {
        Loading({ label: L('Loading conversation…', '正在加载会话…') }).height('100%')
      } else if (this.ctrl.items.length === 0 && !this.ctrl.running) {
        Column({ space: 14 }) {
          AgentAvatar({ agent: this.ctrl.agentType, sz: 56 })
          Text(L(`Start a session with ${agentName(this.ctrl.agentType)}`,
            `开始与 ${agentName(this.ctrl.agentType)} 的会话`)).fontSize(17).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text'))
          Text(this.ctrl.folder !== null && !this.ctrl.folder.isChat ? this.ctrl.folder.path :
          L('A standalone chat with no project folder', '无项目目录的独立对话'))
            .fontSize(13).fontColor($r('app.color.text3')).fontFamily('monospace').textAlign(TextAlign.Center)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(30)
      } else {
        List({ scroller: this.scroller, space: 14 }) {
          ForEach(this.ctrl.items, (it: TItem) => {
            ListItem() {
              this.item(it)
            }
          }, (it: TItem) => it.id)

          if (this.ctrl.plan.length > 0 && this.ctrl.running) {
            ListItem() {
              Column({ space: 8 }) {
                Text(L('Plan', '计划')).fontSize(12).fontColor($r('app.color.text3')).fontWeight(FontWeight.Medium)
                PlanList(this.ctrl.plan)
              }
              .alignItems(HorizontalAlign.Start)
              .padding(12).width('100%').borderRadius(14).backgroundColor($r('app.color.surface'))
            }
          }

          if (this.ctrl.running) {
            ListItem() {
              Row({ space: 8 }) {
                LoadingProgress().width(20).height(20).color($r('app.color.accent'))
                Text(this.ctrl.retrying.length > 0 ? this.ctrl.retrying : L('Working…', '工作中…'))
                  .fontSize(13).fontColor($r('app.color.text3'))
              }.padding({ top: 4, bottom: 4 })
            }
          }

          ForEach(this.ctrl.failures, (f: SessionFailure) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(f.title).fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor(f.severity === 'error' ? $r('app.color.danger') : $r('app.color.warning'))
                if (f.details.length > 0) {
                  Text(f.details).fontSize(12).fontColor($r('app.color.text2')).copyOption(CopyOptions.LocalDevice)
                }
              }
              .alignItems(HorizontalAlign.Start)
              .padding(12).width('100%').borderRadius(12)
              .backgroundColor(f.severity === 'error' ? $r('app.color.danger_soft') : $r('app.color.warning_soft'))
            }
          }, (f: SessionFailure) => `${f.id}-${f.revision}`)

          if (this.ctrl.permission !== null) {
            ListItem() {
              PermissionCard({ req: this.ctrl.permission, onChoose: (id: string) => {
                this.ctrl?.respondPermission(id)
              } })
            }
          }
          if (this.ctrl.question !== null) {
            ListItem() {
              QuestionCard({ req: this.ctrl.question, onAnswer: (a: Map<string, string[]>, d: boolean) => {
                this.ctrl?.answerQuestion(a, d)
              } })
            }
          }
          if (this.ctrl.planApproval !== null) {
            ListItem() {
              PlanApprovalCard({ req: this.ctrl.planApproval, onDecide: (d: string, f: string) => {
                this.ctrl?.answerPlan(d, f.length > 0 ? f : undefined)
              } })
            }
          }
          ListItem() {
            Column().height(12)
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16 })
        .constraintSize({ maxWidth: layout.contentMax })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => {
          this.stickToBottom = true
        })
        .onScrollFrameBegin((offset: number, state: ScrollState) => {
          if (offset < 0 && state === ScrollState.Scroll) {
            this.stickToBottom = false
          }
          return { offsetRemain: offset }
        })
        .onDidScroll(() => {
          try {
            if (this.scroller.isAtEnd()) {
              this.stickToBottom = true
            }
          } catch (e) {
            // Not bound yet.
          }
        })
        .onAppear(() => {
          setTimeout((): void => {
            this.toBottom()
          }, 30)
        })
        .onAreaChange(() => this.scrollDown())
        .onSizeChange(() => this.scrollDown())

        if (!this.stickToBottom) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(sym('chevron_down')).fontSize(18).fontColor([$r('app.color.text')])
          }
          .width(40).height(40).margin(16)
          .backgroundColor($r('app.color.surface'))
          .shadow({ radius: 12, color: '#22000000' })
          .onClick(() => {
            this.stickToBottom = true
            this.toBottom()
          })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  banners() {
    if (this.ctrl !== null && this.ctrl.error.length > 0) {
      Banner({ text: this.ctrl.error, kind: 'error', onClose: () => {
        if (this.ctrl !== null) {
          this.ctrl.error = ''
        }
      } })
    }
    if (this.ctrl !== null && this.ctrl.notice.length > 0) {
      Banner({ text: this.ctrl.notice, kind: 'notice', onClose: () => {
        if (this.ctrl !== null) {
          this.ctrl.notice = ''
        }
      } })
    }
  }

  build() {
    Column() {
      this.header()
      if (layout.halfFolded) {
        // Tent / laptop posture: transcript on the upper half, composer on the lower half.
        Column() {
          this.transcript()
        }
        .height(Math.max(160, layout.creaseTopVp - layout.topInset - 52))
        .width('100%')
        Column().height(layout.creaseHeightVp).width('100%')
        Column() {
          this.banners()
          Composer({ ctrl: this.ctrl, compact: false })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Start)
      } else {
        Column() {
          this.transcript()
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        this.banners()
        Column() {
          Composer({ ctrl: this.ctrl, compact: layout.isCompact })
        }
        .width('100%')
        .constraintSize({ maxWidth: layout.contentMax + 32 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .alignItems(HorizontalAlign.Center)
  }
}
