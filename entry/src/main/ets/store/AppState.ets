import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { Api, HealthInfo, setDeviceIdProvider } from '../net/Api'
import { CodegClient } from '../net/CodegClient'
import { errorText } from '../net/ApiError'
import { AgentInfo, ConversationSummary, ConversationTag, FolderDetail } from '../model/Models'
import { AppPrefs, ServerProfile, ServerStore } from './ServerStore'

/** Process-wide state: the active server, its folders, conversations and agents. */
@ObservedV2
export class AppState {
  store: ServerStore = new ServerStore()
  @Trace servers: ServerProfile[] = []
  @Trace activeId: string = ''
  @Trace api: Api | null = null
  @Trace health: HealthInfo | null = null
  @Trace online: boolean = false
  @Trace folders: FolderDetail[] = []
  @Trace allFolders: FolderDetail[] = []
  @Trace conversations: ConversationSummary[] = []
  @Trace tags: ConversationTag[] = []
  @Trace agents: AgentInfo[] = []
  @Trace loading: boolean = false
  @Trace error: string = ''
  @Trace theme: string = 'system'
  @Trace lastRefresh: number = 0
  /** Conversation id -> when it was last opened here. Bumped to re-render rows. */
  @Trace seenVersion: number = 0
  private seen: Map<number, number> = new Map()
  private pollTimer: number = -1
  private ctx: common.Context | null = null
  private refreshing: boolean = false
  private home: string = ''

  init(ctx: common.Context): void {
    this.ctx = ctx
    this.store.init(ctx)
    AppPrefs.init(ctx)
    setDeviceIdProvider(() => AppPrefs.deviceId())
    this.theme = AppPrefs.get('theme', 'system')
    this.loadSeen()
    this.servers = this.store.list()
    let id = this.store.activeId()
    if (id.length === 0 || this.servers.find((s: ServerProfile) => s.id === id) === undefined) {
      id = this.servers.length > 0 ? this.servers[0].id : ''
    }
    if (id.length > 0) {
      this.activate(id)
    }
  }

  get active(): ServerProfile | undefined {
    return this.servers.find((s: ServerProfile) => s.id === this.activeId)
  }

  activate(id: string): void {
    const p = this.servers.find((s: ServerProfile) => s.id === id)
    if (p === undefined) {
      return
    }
    this.activeId = id
    this.store.setActive(id)
    this.loadSeen()
    this.api = new Api(new CodegClient(p.url, this.store.token(id)))
    this.folders = []
    this.allFolders = []
    this.conversations = []
    this.agents = []
    this.health = null
    this.online = false
    this.home = ''
    this.refresh()
    this.startPolling()
  }

  saveServer(name: string, url: string, token: string | null, id?: string): ServerProfile {
    const p = new ServerProfile()
    const existing = id !== undefined ? this.servers.find((s: ServerProfile) => s.id === id) : undefined
    p.id = existing?.id ?? util.generateRandomUUID(false)
    p.name = name.trim().length > 0 ? name.trim() : url
    p.url = url
    p.createdAt = existing?.createdAt ?? Date.now()
    this.store.upsert(p, token)
    this.servers = this.store.list()
    if (this.activeId === p.id || this.servers.length === 1) {
      this.activate(p.id)
    }
    return p
  }

  removeServer(id: string): void {
    this.store.remove(id)
    this.servers = this.store.list()
    if (this.activeId === id) {
      this.api = null
      this.activeId = ''
      if (this.servers.length > 0) {
        this.activate(this.servers[0].id)
      }
    }
  }

  tokenOf(id: string): string {
    return this.store.token(id)
  }

  setTheme(t: string): void {
    this.theme = t
    AppPrefs.set('theme', t)
    this.applyTheme()
  }

  applyTheme(): void {
    if (this.ctx === null) {
      return
    }
    const mode = this.theme === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      this.theme === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT :
      ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    try {
      this.ctx.getApplicationContext().setColorMode(mode)
    } catch (e) {
      // Ignore on systems without color mode control.
    }
  }

  private startPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer)
    }
    // The server broadcasts list changes, but polling keeps the list honest on flaky links.
    this.pollTimer = setInterval(() => {
      this.refresh(true)
    }, 25000)
  }

  pause(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer)
      this.pollTimer = -1
    }
  }

  resume(): void {
    if (this.api !== null && this.pollTimer < 0) {
      this.refresh(true)
      this.startPolling()
    }
  }

  /** Loads folders, conversations and agents concurrently. */
  async refresh(quiet: boolean = false): Promise<void> {
    const api = this.api
    if (api === null || this.refreshing) {
      return
    }
    this.refreshing = true
    if (!quiet) {
      this.loading = true
    }
    try {
      const results = await Promise.all([
        api.health(), api.allFolders(), api.openFolders(), api.conversations()
      ])
      if (api !== this.api) {
        return
      }
      this.health = results[0] as HealthInfo
      this.allFolders = results[1] as FolderDetail[]
      this.folders = (results[2] as FolderDetail[]).sort((a: FolderDetail, b: FolderDetail) => a.sortOrder - b.sortOrder)
      this.conversations = results[3] as ConversationSummary[]
      this.online = true
      this.error = ''
      this.lastRefresh = Date.now()
      if (this.agents.length === 0) {
        api.agents().then((a: AgentInfo[]) => {
          this.agents = a
        }).catch(() => {
        })
        api.tags().then((t: ConversationTag[]) => {
          this.tags = t
        })
      }
    } catch (e) {
      if (api === this.api) {
        this.online = false
        this.error = errorText(e)
      }
    } finally {
      this.refreshing = false
      this.loading = false
    }
  }

  private seenKey(): string {
    return `seen.${this.activeId}`
  }

  private loadSeen(): void {
    this.seen = new Map()
    try {
      const o = JSON.parse(AppPrefs.get(this.seenKey(), '{}')) as Record<string, number>
      for (const k of Object.keys(o)) {
        this.seen.set(Number(k), o[k])
      }
    } catch (e) {
      // Corrupt entry; start fresh.
    }
    this.seenVersion++
  }

  /** Records that the user opened a conversation (local to this device, server status untouched). */
  markSeen(id: number): void {
    // Use the server's timestamp as a floor so a phone clock behind the server
    // doesn't leave the row flagged.
    const c = this.conversationById(id)
    this.seen.set(id, Math.max(Date.now(), (c?.updatedAt ?? 0) + 1))
    const o: Record<string, number> = {}
    this.seen.forEach((v: number, k: number) => {
      o[`${k}`] = v
    })
    AppPrefs.set(this.seenKey(), JSON.stringify(o))
    this.seenVersion++
  }

  /**
   * The server marks every finished turn `pending_review` and never clears it on
   * view, so most sessions carry it. Treat it as "needs review" only while there
   * is activity the user hasn't opened yet.
   */
  needsReview(c: ConversationSummary): boolean {
    if (c.status !== 'pending_review' || this.seenVersion < 0) {
      return false
    }
    const seenAt = this.seen.get(c.id) ?? 0
    return c.updatedAt > seenAt
  }

  /** Home directory of the user the server runs as (what `~/` means in an agent's reply); '' if unknown. */
  async homeDir(): Promise<string> {
    if (this.home.length === 0 && this.api !== null) {
      try {
        this.home = await this.api.homeDirectory()
      } catch (e) {
        this.home = ''
      }
    }
    return this.home
  }

  folderById(id: number): FolderDetail | null {
    return this.allFolders.find((f: FolderDetail) => f.id === id) ??
      this.folders.find((f: FolderDetail) => f.id === id) ?? null
  }

  conversationById(id: number): ConversationSummary | undefined {
    return this.conversations.find((c: ConversationSummary) => c.id === id)
  }

  conversationsIn(folderId: number): ConversationSummary[] {
    return this.conversations.filter((c: ConversationSummary) => c.folderId === folderId)
      .sort((a: ConversationSummary, b: ConversationSummary) => b.updatedAt - a.updatedAt)
  }

  get enabledAgents(): AgentInfo[] {
    return this.agents.filter((a: AgentInfo) => a.enabled)
  }

  defaultAgent(folder: FolderDetail | null): string {
    if (folder !== null && folder.defaultAgentType !== undefined) {
      return folder.defaultAgentType
    }
    const last = AppPrefs.get('last_agent')
    if (last.length > 0) {
      return last
    }
    const e = this.enabledAgents
    return e.length > 0 ? e[0].agentType : 'claude_code'
  }

  async mutateConversation(f: (api: Api) => Promise<void>): Promise<void> {
    if (this.api === null) {
      return
    }
    try {
      await f(this.api)
    } catch (e) {
      this.error = errorText(e)
    }
    await this.refresh(true)
  }
}

export const app: AppState = new AppState()
