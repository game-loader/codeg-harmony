import { app } from '../store/AppState'
import { Api } from '../net/Api'
import { ConversationSummary, FolderDetail } from '../model/Models'
import { L, relativeTime } from '../common/I18n'
import { STATUSES, agentName, statusLabel, statusColor } from '../common/Agents'
import { AgentAvatar, EmptyState, IconButton, Loading, PaneTitle, sym } from '../components/Common'

class Group {
  key: string = ''
  title: string = ''
  items: ConversationSummary[] = []
}

@ComponentV2
export struct SessionRow {
  @Param conv: ConversationSummary = new ConversationSummary()
  @Param folderName: string = ''
  @Param selected: boolean = false

  build() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        AgentAvatar({ agent: this.conv.agentType, sz: 38 })
        if (this.conv.status === 'in_progress' || app.needsReview(this.conv)) {
          Circle().width(11).height(11).fill(statusColor(this.conv.status))
            .stroke($r('app.color.surface')).strokeWidth(2)
        }
      }
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          if (this.conv.pinnedAt !== undefined) {
            SymbolGlyph(sym('pin_fill')).fontSize(11).fontColor([$r('app.color.warning')])
          }
          Text(this.conv.displayTitle).fontSize(15.5).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(relativeTime(this.conv.updatedAt)).fontSize(11).fontColor($r('app.color.text3'))
        }.width('100%')
        Row({ space: 6 }) {
          Text(agentName(this.conv.agentType)).fontSize(12).fontColor($r('app.color.text3'))
          if (this.folderName.length > 0) {
            Text(`· ${this.folderName}`).fontSize(12).fontColor($r('app.color.text3')).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          } else {
            Blank()
          }
          if (this.conv.status === 'in_progress' || this.conv.status === 'cancelled' || app.needsReview(this.conv)) {
            Text(statusLabel(this.conv.status)).fontSize(11).fontColor(statusColor(this.conv.status))
          }
        }.width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .margin({ left: 10, right: 10 })
    .borderRadius(14)
    .backgroundColor(this.selected ? $r('app.color.accent_soft') : Color.Transparent)
  }
}

@ComponentV2
export struct SessionsList {
  @Param selectedId: number = 0
  @Param folderFilter: number = 0
  @Param title: string = ''
  @Event onOpen: (c: ConversationSummary) => void = (c: ConversationSummary) => {
  }
  @Event onNew: () => void = () => {
  }
  @Event onBack: () => void = () => {
  }
  @Param showBack: boolean = false
  @Local status: string = ''
  @Local query: string = ''
  @Local grouping: string = 'time'
  @Local renaming: ConversationSummary | null = null
  @Local renameText: string = ''
  @Local showRename: boolean = false

  folderName(id: number): string {
    return app.folderById(id)?.displayName ?? ''
  }

  @Computed
  get filtered(): ConversationSummary[] {
    const q = this.query.trim().toLowerCase()
    return app.conversations.filter((c: ConversationSummary) => {
      if (this.folderFilter > 0 && c.folderId !== this.folderFilter) {
        return false
      }
      if (this.status.length > 0 && c.status !== this.status) {
        return false
      }
      if (q.length > 0) {
        const hay = `${c.title ?? ''} ${agentName(c.agentType)} ${this.folderName(c.folderId)}`.toLowerCase()
        return hay.includes(q)
      }
      return true
    }).sort((a: ConversationSummary, b: ConversationSummary) => b.updatedAt - a.updatedAt)
  }

  @Computed
  get groups(): Group[] {
    const list = this.filtered
    const pinned = list.filter((c: ConversationSummary) => c.pinnedAt !== undefined)
    const rest = list.filter((c: ConversationSummary) => c.pinnedAt === undefined)
    const out: Group[] = []
    if (pinned.length > 0) {
      const g = new Group()
      g.key = 'pinned'
      g.title = L('Pinned', '已置顶')
      g.items = pinned
      out.push(g)
    }
    if (this.grouping === 'folder' && this.folderFilter === 0) {
      const map: Map<number, Group> = new Map()
      for (const c of rest) {
        let g = map.get(c.folderId)
        if (g === undefined) {
          g = new Group()
          g.key = `f${c.folderId}`
          const f: FolderDetail | null = app.folderById(c.folderId)
          g.title = f === null ? L('Other', '其他') : f.isChat ? L('Chats', '对话') : f.displayName
          map.set(c.folderId, g)
          out.push(g)
        }
        g.items.push(c)
      }
      return out
    }
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const buckets: string[] = [L('Today', '今天'), L('Yesterday', '昨天'), L('This week', '本周'), L('Earlier', '更早')]
    const gs: Group[] = buckets.map((t: string, i: number) => {
      const g = new Group()
      g.key = `t${i}`
      g.title = t
      return g
    })
    for (const c of rest) {
      const t = c.updatedAt
      const idx = t >= today ? 0 : t >= today - 86400000 ? 1 : t >= today - 6 * 86400000 ? 2 : 3
      gs[idx].items.push(c)
    }
    return out.concat(gs.filter((g: Group) => g.items.length > 0))
  }

  @Builder
  swipeActions(c: ConversationSummary) {
    Row() {
      Column({ space: 4 }) {
        SymbolGlyph(sym(c.pinnedAt !== undefined ? 'pin_slash' : 'pin')).fontSize(18).fontColor([Color.White])
        Text(c.pinnedAt !== undefined ? L('Unpin', '取消置顶') : L('Pin', '置顶')).fontSize(11).fontColor(Color.White)
      }
      .width(72).height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.warning'))
      .onClick(() => {
        app.mutateConversation((api: Api): Promise<void> => api.setPinned(c.id, c.pinnedAt === undefined))
      })
      Column({ space: 4 }) {
        SymbolGlyph(sym('checkmark')).fontSize(18).fontColor([Color.White])
        Text(L('Done', '完成')).fontSize(11).fontColor(Color.White)
      }
      .width(72).height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.success'))
      .onClick(() => {
        app.mutateConversation((api: Api): Promise<void> => api.setStatus(c.id, 'completed'))
      })
      Column({ space: 4 }) {
        SymbolGlyph(sym('trash')).fontSize(18).fontColor([Color.White])
        Text(L('Delete', '删除')).fontSize(11).fontColor(Color.White)
      }
      .width(72).height('100%').justifyContent(FlexAlign.Center).backgroundColor($r('app.color.danger'))
      .onClick(() => this.confirmDelete(c))
    }.height('100%')
  }

  confirmDelete(c: ConversationSummary): void {
    this.getUIContext().showAlertDialog({
      title: L('Delete conversation?', '删除会话？'),
      message: c.displayTitle,
      primaryButton: { value: L('Cancel', '取消'), action: () => {
      } },
      secondaryButton: {
        value: L('Delete', '删除'), fontColor: $r('app.color.danger'), action: () => {
          app.mutateConversation((api: Api): Promise<void> => api.deleteConversation(c.id))
        }
      }
    })
  }

  @Builder
  rowMenu(c: ConversationSummary) {
    Menu() {
      MenuItem({ content: L('Rename', '重命名') }).onClick(() => {
        this.renaming = c
        this.renameText = c.title ?? ''
        this.showRename = true
      })
      MenuItem({ content: c.pinnedAt !== undefined ? L('Unpin', '取消置顶') : L('Pin', '置顶') }).onClick(() => {
        app.mutateConversation((api: Api): Promise<void> => api.setPinned(c.id, c.pinnedAt === undefined))
      })
      MenuItemGroup({ header: L('Status', '状态') }) {
        ForEach(STATUSES, (s: string) => {
          MenuItem({ content: statusLabel(s) }).selected(c.status === s).onClick(() => {
            app.mutateConversation((api: Api): Promise<void> => api.setStatus(c.id, s))
          })
        }, (s: string) => s)
      }
      MenuItem({ content: L('Delete', '删除') }).onClick(() => this.confirmDelete(c))
    }
  }

  @Builder
  renameSheet() {
    Column({ space: 14 }) {
      Text(L('Rename', '重命名')).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
      TextInput({ text: this.renameText }).height(46).backgroundColor($r('app.color.surface2'))
        .onChange((v: string) => {
          this.renameText = v
        })
      Button(L('Save', '保存')).type(ButtonType.Capsule).height(44).width('100%')
        .backgroundColor($r('app.color.accent'))
        .onClick(() => {
          const c = this.renaming
          const t = this.renameText.trim()
          this.showRename = false
          if (c !== null && t.length > 0) {
            app.mutateConversation((api: Api): Promise<void> => api.setTitle(c.id, t))
          }
        })
    }
    .padding(20).width('100%')
  }

  @Builder
  filterChip(value: string, label: string) {
    Text(label)
      .fontSize(13)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .fontColor(this.status === value ? Color.White : $r('app.color.text2'))
      .backgroundColor(this.status === value ? $r('app.color.accent') : $r('app.color.surface'))
      .onClick(() => {
        this.status = value
      })
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        if (this.showBack) {
          IconButton({ icon: 'chevron_left', sz: 22, color: $r('app.color.text'), onTap: () => this.onBack() })
        }
        Column({ space: 2 }) {
          Text(this.title.length > 0 ? this.title : L('Sessions', '会话')).fontSize(26).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(app.active !== undefined ? `${app.active.name}${app.online ? '' : L(' · offline', ' · 离线')}` : '')
            .fontSize(12).fontColor(app.online ? $r('app.color.text3') : $r('app.color.danger')).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (this.folderFilter === 0) {
          IconButton({
            icon: this.grouping === 'folder' ? 'folder' : 'clock', sz: 19, onTap: () => {
              this.grouping = this.grouping === 'folder' ? 'time' : 'folder'
            }
          })
        }
        IconButton({ icon: 'square_and_pencil', sz: 20, color: $r('app.color.accent'), onTap: () => this.onNew() })
      }
      .padding({ left: this.showBack ? 6 : 20, right: 10, top: 10, bottom: 6 })
      .width('100%')

      Search({ value: this.query, placeholder: L('Search sessions', '搜索会话') })
        .height(40)
        .margin({ left: 16, right: 16 })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => {
          this.query = v
        })

      Scroll() {
        Row({ space: 8 }) {
          this.filterChip('', L('All', '全部'))
          ForEach(STATUSES, (s: string) => {
            this.filterChip(s, statusLabel(s))
          }, (s: string) => s)
        }.padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .margin({ top: 10, bottom: 4 })
      .width('100%')

      if (app.loading && app.conversations.length === 0) {
        Loading().layoutWeight(1)
      } else if (this.filtered.length === 0) {
        EmptyState({
          icon: 'message', title: L('No sessions', '暂无会话'),
          message: app.online ? L('Start a new session with any agent.', '与任意智能体开始一个新会话。') : app.error,
          action: app.online ? L('New session', '新建会话') : L('Retry', '重试'),
          onAction: () => {
            if (app.online) {
              this.onNew()
            } else {
              app.refresh()
            }
          }
        }).layoutWeight(1)
      } else {
        Refresh({ refreshing: app.loading }) {
          List({ space: 2 }) {
            ForEach(this.groups, (g: Group) => {
              ListItemGroup({ header: this.groupHeader(g.title) }) {
                ForEach(g.items, (c: ConversationSummary) => {
                  ListItem() {
                    SessionRow({ conv: c, folderName: this.folderFilter > 0 ? '' : this.folderName(c.folderId),
                      selected: c.id === this.selectedId })
                      .onClick(() => this.onOpen(c))
                      .bindContextMenu(this.rowMenu(c), ResponseType.LongPress)
                  }
                  .swipeAction({ end: { builder: () => {
                    this.swipeActions(c)
                  } } })
                }, (c: ConversationSummary) => `${c.id}-${c.updatedAt}-${c.status}-${c.pinnedAt ?? 0}-${c.title ?? ''}`)
              }
            }, (g: Group) => `${g.key}-${g.items.length}`)
            ListItem() {
              Column().height(90)
            }
          }
          .sticky(StickyStyle.Header)
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }
        .onRefreshing(() => {
          app.refresh()
        })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .bindSheet($$this.showRename, this.renameSheet(), { height: 240, dragBar: true })
  }

  @Builder
  groupHeader(title: string) {
    Text(title).fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.text3'))
      .padding({ left: 24, top: 12, bottom: 6 }).width('100%').backgroundColor($r('app.color.bg'))
  }
}
