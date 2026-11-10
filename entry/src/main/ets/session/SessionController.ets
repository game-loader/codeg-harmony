import { util } from '@kit.ArkTS'
import { JObj, arr, asObj, has, num, obj, str } from '../common/Json'
import { Api, UploadedAttachment } from '../net/Api'
import { ApiError, errorText } from '../net/ApiError'
import { EventSocket, EventSocketListener } from '../net/EventSocket'
import { ConversationSummary, FolderDetail } from '../model/Models'
import { AppPrefs } from '../store/ServerStore'
import { L } from '../common/I18n'
import {
  ImageRef, ItemKind, PlanEntry, TItem, ToolCall, applyToolUpdate, itemsFromTurns, toolFromEvent
} from './Transcript'
import {
  AgentOptions, PermissionRequest, PlanApproval, QuestionRequest, SessionFailure
} from './Interactive'

export class PendingImage {
  data: string = ''
  mimeType: string = 'image/jpeg'
  name: string = ''
}

export class Draft {
  text: string = ''
  images: PendingImage[] = []
  files: UploadedAttachment[] = []
}

function uuid(): string {
  return util.generateRandomUUID(false)
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((r: () => void) => {
    setTimeout(r, ms)
  })
}

/**
 * Owns one open conversation: history, live stream and interactive cards.
 * Turn flow: create (draft) → find/connect → ws attach → acp_prompt → stream
 * until turn_complete → refetch persisted turns.
 */
@ObservedV2
export class SessionController {
  api: Api
  @Trace conversationId: number = 0
  @Trace folder: FolderDetail | null = null
  @Trace agentType: string = 'claude_code'
  @Trace title: string = ''
  @Trace status: string = ''
  @Trace items: TItem[] = []
  @Trace loading: boolean = false
  @Trace running: boolean = false
  @Trace connState: string = 'idle'
  @Trace error: string = ''
  @Trace notice: string = ''
  @Trace permission: PermissionRequest | null = null
  @Trace question: QuestionRequest | null = null
  @Trace planApproval: PlanApproval | null = null
  @Trace plan: PlanEntry[] = []
  @Trace failures: SessionFailure[] = []
  @Trace usedTokens: number = 0
  @Trace contextSize: number = 0
  @Trace options: AgentOptions | null = null
  @Trace queued: string[] = []
  @Trace retrying: string = ''
  @Trace version: number = 0
  summary: ConversationSummary | null = null
  externalId: string | undefined = undefined
  connectionId: string | null = null
  paperId: string | undefined = undefined
  private socket: EventSocket | null = null
  private subscriptionId: string = ''
  private attached: boolean = false
  private attachWaiters: Array<(ok: boolean) => void> = []
  private liveText: TItem | null = null
  private liveThinking: TItem | null = null
  private liveTools: Map<string, ToolCall> = new Map()
  private liveItems: TItem[] = []
  private historyItems: TItem[] = []
  private disposed: boolean = false
  onListChanged: () => void = () => {
  }
  onSeen: (id: number) => void = (id: number) => {
  }

  constructor(api: Api) {
    this.api = api
  }

  // ---------- lifecycle ----------

  /** Opens an existing conversation and re-attaches if its turn is still running. */
  async open(conversationId: number, folder: FolderDetail | null): Promise<void> {
    this.conversationId = conversationId
    this.folder = folder
    this.loading = true
    try {
      await this.reloadHistory()
      await this.reattachIfLive()
    } catch (e) {
      this.error = errorText(e)
    } finally {
      this.loading = false
    }
  }

  /** A new conversation that exists only locally until the first send. */
  startDraft(folder: FolderDetail | null, agentType: string): void {
    this.conversationId = 0
    this.folder = folder
    this.agentType = agentType
    this.title = L('New session', '新会话')
    this.items = []
    this.historyItems = []
  }

  async reloadHistory(): Promise<void> {
    if (this.conversationId <= 0) {
      return
    }
    const d = await this.api.conversation(this.conversationId)
    this.summary = d.summary
    this.agentType = d.summary.agentType
    this.title = d.summary.displayTitle
    this.status = d.summary.status
    this.externalId = d.summary.externalId
    if (d.stats !== undefined && d.stats.contextMax > 0) {
      this.usedTokens = d.stats.contextUsed
      this.contextSize = d.stats.contextMax
    }
    this.historyItems = itemsFromTurns(d.turns)
    this.rebuild()
    this.onSeen(this.conversationId)
  }

  private rebuild(): void {
    this.items = this.historyItems.concat(this.liveItems)
    this.version++
  }

  private async reattachIfLive(): Promise<void> {
    if (this.conversationId <= 0) {
      return
    }
    let cid: string | null = null
    try {
      cid = await this.api.findConnection(this.conversationId, this.agentType, this.externalId)
    } catch (e) {
      return
    }
    if (cid === null) {
      return
    }
    this.connectionId = cid
    await this.ensureAttached()
    this.loadOptions()
  }

  dispose(): void {
    this.disposed = true
    if (this.socket !== null) {
      if (this.attached) {
        this.socket.detach(this.subscriptionId)
      }
      this.socket.close()
      this.socket = null
    }
  }

  // ---------- socket ----------

  private ensureSocket(): Promise<boolean> {
    if (this.socket !== null && this.socket.isOpen) {
      return Promise.resolve(true)
    }
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      let settled = false
      const done = (ok: boolean) => {
        if (!settled) {
          settled = true
          resolve(ok)
        }
      }
      const listener = new SessionSocketListener(this, done)
      this.attached = false
      this.socket = new EventSocket(this.api.c, listener)
      this.socket.open()
      setTimeout((): void => { done(false) }, 12000)
    })
  }

  handleClosed(reason: string): void {
    this.attached = false
    this.socket = null
    this.flushWaiters(false)
    if (this.disposed) {
      return
    }
    if (this.running) {
      this.connState = 'reconnecting'
      // Reconnect after a short pause; the snapshot rebuilds the live turn.
      setTimeout(() => {
        if (!this.disposed && this.connectionId !== null) {
          this.ensureAttached().catch(() => {
          })
        }
      }, 1500)
    } else {
      this.connState = 'idle'
    }
  }

  private flushWaiters(ok: boolean): void {
    const ws = this.attachWaiters
    this.attachWaiters = []
    ws.forEach((w: (ok: boolean) => void) => w(ok))
  }

  /** Attaches to the current connection and waits for the snapshot or replay. */
  private async ensureAttached(): Promise<boolean> {
    if (this.connectionId === null) {
      return false
    }
    if (this.attached && this.socket !== null && this.socket.isOpen) {
      return true
    }
    this.connState = 'connecting'
    const ok = await this.ensureSocket()
    if (!ok || this.socket === null) {
      this.connState = 'offline'
      return false
    }
    this.subscriptionId = uuid()
    const waiter = new Promise<boolean>((resolve: (ok: boolean) => void) => {
      this.attachWaiters.push(resolve)
      setTimeout((): void => { resolve(false) }, 12000)
    })
    this.socket.attach(this.subscriptionId, this.connectionId)
    const attached = await waiter
    this.connState = attached ? 'connected' : 'offline'
    return attached
  }

  handleFrame(type: string, frame: JObj): void {
    switch (type) {
      case 'snapshot':
        this.attached = true
        this.applySnapshot(obj(frame, 'snapshot'))
        this.flushWaiters(true)
        return
      case 'replay':
        this.attached = true
        for (const e of arr(frame, 'events')) {
          this.onEvent(asObj(e))
        }
        this.flushWaiters(true)
        return
      case 'event':
        this.onEvent(obj(frame, 'envelope'))
        return
      case 'detached':
        this.attached = false
        if (str(frame, 'reason') === 'connection_gone') {
          this.connectionId = null
          if (this.running) {
            this.endTurn()
          }
        }
        this.flushWaiters(false)
        return
      default:
        return
    }
  }

  // ---------- snapshot & events ----------

  private resetLive(): void {
    this.liveItems = []
    this.liveText = null
    this.liveThinking = null
    this.liveTools = new Map()
  }

  private applySnapshot(s: JObj): void {
    this.resetLive()
    const status = str(s, 'status')
    this.running = status === 'prompting'
    const content = arr(obj(s, 'live_message'), 'content')
    const tools: Map<string, ToolCall> = new Map()
    for (const t of arr(s, 'active_tool_calls')) {
      const tc = toolFromEvent(asObj(t))
      tools.set(tc.id, tc)
    }
    for (const c of content) {
      const co = asObj(c)
      const kind = str(co, 'kind')
      if (kind === 'text') {
        this.appendText(str(co, 'text'), false)
      } else if (kind === 'thinking') {
        this.appendText(str(co, 'text'), true)
      } else if (kind === 'tool_call_ref') {
        const tc = tools.get(str(co, 'tool_call_id'))
        if (tc !== undefined) {
          this.pushTool(tc)
        }
      } else if (kind === 'plan') {
        this.plan = arr(co, 'entries').map((v: Object) => PlanEntry.from(v))
      }
    }
    this.permission = has(s, 'pending_permission') ? PermissionRequest.from(obj(s, 'pending_permission')) : null
    this.question = has(s, 'pending_question') ? QuestionRequest.from(obj(s, 'pending_question')) : null
    this.planApproval = has(s, 'pending_plan_approval') ? PlanApproval.from(obj(s, 'pending_plan_approval')) : null
    this.failures = arr(s, 'session_failures').map((v: Object) => SessionFailure.from(asObj(v)))
      .filter((f: SessionFailure) => !f.resolved)
    if (has(s, 'last_error') && this.running) {
      this.error = str(obj(s, 'last_error'), 'message')
    }
    if (this.running) {
      this.markLive()
    }
    this.rebuild()
  }

  private markLive(): void {
    if (this.liveItems.length === 0 || this.liveItems[this.liveItems.length - 1].kind !== ItemKind.Notice) {
      // The trailing activity indicator is rendered by the view from `running`.
    }
  }

  private appendText(text: string, thinking: boolean): void {
    if (text.length === 0) {
      return
    }
    if (thinking) {
      if (this.liveThinking === null) {
        this.liveThinking = new TItem(`lt-${uuid()}`, ItemKind.Thinking)
        this.liveThinking.live = true
        this.liveItems.push(this.liveThinking)
        this.liveText = null
      }
      this.liveThinking.text += text
    } else {
      if (this.liveText === null) {
        this.liveText = new TItem(`lx-${uuid()}`, ItemKind.Text)
        this.liveText.live = true
        this.liveItems.push(this.liveText)
        this.liveThinking = null
      }
      this.liveText.text += text
    }
  }

  private pushTool(tc: ToolCall): void {
    this.liveTools.set(tc.id, tc)
    const it = new TItem(`lc-${tc.id}`, ItemKind.Tool)
    it.tool = tc
    it.live = true
    this.liveItems.push(it)
    this.liveText = null
    this.liveThinking = null
  }

  private onEvent(e: JObj): void {
    const type = str(e, 'type')
    let structural = false
    switch (type) {
      case 'content_delta':
      case 'thinking': {
        const parent = str(e, 'parent_tool_use_id')
        if (parent.length > 0) {
          const tc = this.liveTools.get(parent)
          if (tc !== undefined) {
            tc.subText += str(e, 'text')
          }
          return
        }
        const before = this.liveItems.length
        this.appendText(str(e, 'text'), type === 'thinking')
        this.running = true
        this.retrying = ''
        structural = this.liveItems.length !== before
        break
      }
      case 'tool_call': {
        const tc = toolFromEvent(e)
        const existing = this.liveTools.get(tc.id)
        if (existing !== undefined) {
          applyToolUpdate(existing, e)
        } else {
          this.pushTool(tc)
          structural = true
        }
        this.running = true
        break
      }
      case 'tool_call_update': {
        const tc = this.liveTools.get(str(e, 'tool_call_id'))
        if (tc !== undefined) {
          applyToolUpdate(tc, e)
        }
        break
      }
      case 'plan_update':
        this.plan = arr(e, 'entries').map((v: Object) => PlanEntry.from(v))
        break
      case 'turn_complete':
        this.endTurn()
        return
      case 'session_started':
        this.externalId = str(e, 'session_id')
        break
      case 'conversation_linked':
        if (this.conversationId <= 0) {
          this.conversationId = num(e, 'conversation_id')
          this.onListChanged()
        }
        break
      case 'conversation_status_changed':
        this.status = str(e, 'status')
        this.onListChanged()
        break
      case 'status_changed': {
        const s = str(e, 'status')
        if (s === 'prompting') {
          this.running = true
        } else if ((s === 'disconnected' || s === 'error') && this.running) {
          this.connectionId = null
          this.endTurn()
        }
        break
      }
      case 'usage_update':
        this.usedTokens = num(e, 'used')
        this.contextSize = num(e, 'size')
        break
      case 'error':
        this.error = str(e, 'message')
        break
      case 'session_failure': {
        const f = SessionFailure.from(obj(e, 'record'))
        const others = this.failures.filter((x: SessionFailure) => x.id !== f.id)
        const old = this.failures.find((x: SessionFailure) => x.id === f.id)
        if (old !== undefined && old.revision >= f.revision) {
          break
        }
        this.failures = f.resolved ? others : others.concat([f])
        break
      }
      case 'turn_retrying':
        this.retrying = str(e, 'message')
        break
      case 'session_notice':
        this.notice = str(obj(e, 'notice'), 'title')
        break
      case 'session_load_failed':
        this.error = str(e, 'message')
        break
      case 'permission_request':
        this.permission = PermissionRequest.from(e)
        break
      case 'permission_resolved':
        if (this.permission !== null && this.permission.requestId === str(e, 'request_id')) {
          this.permission = null
        }
        break
      case 'question_request':
        this.question = QuestionRequest.from(e)
        break
      case 'question_resolved':
        if (this.question !== null && this.question.questionId === str(e, 'question_id')) {
          this.question = null
        }
        break
      case 'plan_approval_request':
        this.planApproval = PlanApproval.from(e)
        break
      case 'plan_approval_resolved':
        this.planApproval = null
        break
      default:
        return
    }
    if (structural) {
      this.rebuild()
    }
  }

  private endTurn(): void {
    const wasRunning = this.running
    this.running = false
    this.permission = null
    this.question = null
    this.planApproval = null
    this.retrying = ''
    this.liveItems.forEach((it: TItem) => {
      it.live = false
    })
    this.onListChanged()
    this.reloadHistory().then(() => {
      this.resetLive()
      this.rebuild()
      if (wasRunning && this.queued.length > 0) {
        const next = this.queued[0]
        this.queued = this.queued.slice(1)
        const d = new Draft()
        d.text = next
        this.send(d)
      }
    }).catch(() => {
    })
  }

  // ---------- sending ----------

  private selectorPrefs(): JObj {
    try {
      return asObj(JSON.parse(AppPrefs.get(`selectors.${this.agentType}`, '{}')) as Object)
    } catch (e) {
      return {} as JObj
    }
  }

  private async connect(resume: boolean): Promise<string> {
    const prefs = this.selectorPrefs()
    const mode = str(prefs, 'mode')
    const cfg = obj(prefs, 'config')
    const id = await this.api.connect(this.agentType, this.folder?.path,
      resume ? this.externalId : undefined, mode.length > 0 ? mode : undefined,
      Object.keys(cfg).length > 0 ? cfg : undefined)
    this.connectionId = id
    return id
  }

  private async resolveConnection(): Promise<void> {
    if (this.connectionId !== null) {
      return
    }
    if (this.conversationId > 0) {
      const found = await this.api.findConnection(this.conversationId, this.agentType, this.externalId)
      if (found !== null) {
        this.connectionId = found
        return
      }
    }
    await this.connect(this.externalId !== undefined && this.externalId.length > 0)
  }

  private buildBlocks(d: Draft): JObj[] {
    const blocks: JObj[] = []
    if (d.text.trim().length > 0) {
      blocks.push({ 'type': 'text', 'text': d.text } as JObj)
    }
    for (const im of d.images) {
      blocks.push({ 'type': 'image', 'data': im.data, 'mime_type': im.mimeType } as JObj)
    }
    for (const f of d.files) {
      blocks.push({ 'type': 'resource_link', 'uri': f.fileUri, 'name': f.name, 'mime_type': f.mimeType } as JObj)
    }
    return blocks
  }

  /** Returns false when the draft should be restored into the composer. */
  async send(d: Draft): Promise<boolean> {
    const blocks = this.buildBlocks(d)
    if (blocks.length === 0) {
      return true
    }
    if (this.running) {
      // Steering: deliver mid-turn if the agent supports it, else queue locally.
      if (this.connectionId !== null && d.images.length === 0 && d.files.length === 0) {
        try {
          await this.api.submitFeedback(this.connectionId, d.text)
          this.notice = L('Sent to the running turn', '已发送到当前回合')
          return true
        } catch (e) {
          // Fall back to the local queue.
        }
      }
      this.queued = this.queued.concat([d.text])
      return true
    }
    this.error = ''
    this.notice = ''
    try {
      if (this.conversationId <= 0) {
        const first = d.text.split('\n')[0].trim()
        const title = first.length > 80 ? first.substring(0, 80) : first
        if (this.folder !== null && !this.folder.isChat) {
          this.conversationId = await this.api.createConversation(this.folder.id, this.agentType,
            title.length > 0 ? title : undefined, this.paperId)
        } else {
          const r = await this.api.createChatConversation(this.agentType, title.length > 0 ? title : undefined, this.paperId)
          this.conversationId = r[0]
        }
        this.title = title.length > 0 ? title : this.title
        this.onListChanged()
      }
      // Optimistic user bubble.
      const u = new TItem(`pu-${uuid()}`, ItemKind.User)
      u.text = d.text
      u.pending = true
      u.images = d.images.map((p: PendingImage) => {
        const r = new ImageRef()
        r.data = p.data
        r.mimeType = p.mimeType
        return r
      })
      this.resetLive()
      this.liveItems.push(u)
      this.running = true
      this.rebuild()
      await this.resolveConnection()
      await this.promptWithRecovery(blocks)
      u.pending = false
      return true
    } catch (e) {
      this.running = false
      this.resetLive()
      this.rebuild()
      if (e instanceof ApiError && (e as ApiError).isTurnInProgress) {
        this.notice = L('A turn is already running', '已有回合正在进行')
      } else {
        this.error = errorText(e)
      }
      return false
    }
  }

  private async promptWithRecovery(blocks: JObj[]): Promise<void> {
    for (let attempt = 0; attempt < 2; attempt++) {
      const ok = await this.ensureAttached()
      if (!ok) {
        if (attempt === 0) {
          this.connectionId = null
          await this.connect(this.externalId !== undefined && this.externalId.length > 0)
          continue
        }
        throw new ApiError(0, 'network', L('Could not subscribe to the session', '无法订阅会话事件'))
      }
      try {
        await this.api.prompt(this.connectionId ?? '', blocks, this.folder?.id,
          this.conversationId > 0 ? this.conversationId : undefined, uuid())
        return
      } catch (e) {
        if (attempt === 0 && e instanceof ApiError && (e as ApiError).isStaleConnection) {
          this.detachQuietly()
          this.connectionId = null
          await this.connect(this.externalId !== undefined && this.externalId.length > 0)
          await sleep(100)
          continue
        }
        throw e as Error
      }
    }
  }

  private detachQuietly(): void {
    if (this.socket !== null && this.attached) {
      this.socket.detach(this.subscriptionId)
    }
    this.attached = false
  }

  async cancel(): Promise<void> {
    if (this.connectionId === null) {
      this.running = false
      return
    }
    try {
      await this.api.cancel(this.connectionId)
    } catch (e) {
      this.error = errorText(e)
    }
  }

  async respondPermission(optionId: string): Promise<void> {
    const p = this.permission
    if (p === null || this.connectionId === null) {
      return
    }
    this.permission = null
    try {
      await this.api.respondPermission(this.connectionId, p.requestId, optionId)
    } catch (e) {
      this.permission = p
      this.error = errorText(e)
    }
  }

  async answerQuestion(answers: Map<string, string[]>, declined: boolean): Promise<void> {
    const q = this.question
    if (q === null || this.connectionId === null) {
      return
    }
    this.question = null
    const list: JObj[] = []
    answers.forEach((labels: string[], id: string) => {
      list.push({ 'questionId': id, 'labels': labels } as JObj)
    })
    try {
      await this.api.answerQuestion(this.connectionId, q.questionId, declined ? [] : list, declined)
    } catch (e) {
      this.question = q
      this.error = errorText(e)
    }
  }

  async answerPlan(decision: string, feedback?: string): Promise<void> {
    const p = this.planApproval
    if (p === null || this.connectionId === null) {
      return
    }
    this.planApproval = null
    try {
      await this.api.answerPlanApproval(this.connectionId, p.approvalId, decision, feedback)
    } catch (e) {
      this.planApproval = p
      this.error = errorText(e)
    }
  }

  // ---------- agent options (mode / model) ----------

  async loadOptions(): Promise<void> {
    try {
      let snap: JObj | null = null
      if (this.connectionId !== null) {
        snap = await this.api.sessionSnapshot(this.connectionId)
      } else if (this.conversationId > 0) {
        snap = await this.api.sessionSnapshot(undefined, this.conversationId)
      }
      if (snap === null) {
        snap = await this.api.describeAgentOptions(this.agentType, this.folder?.path)
      }
      this.options = AgentOptions.from(snap)
    } catch (e) {
      // Selectors are optional.
    }
  }

  async setMode(modeId: string): Promise<void> {
    const prefs = this.selectorPrefs()
    prefs['mode'] = modeId
    AppPrefs.set(`selectors.${this.agentType}`, JSON.stringify(prefs))
    if (this.options !== null) {
      this.options.currentMode = modeId
      this.version++
    }
    if (this.connectionId !== null) {
      try {
        await this.api.setMode(this.connectionId, modeId)
      } catch (e) {
        this.error = errorText(e)
      }
    }
  }

  async setConfig(configId: string, value: string): Promise<void> {
    const prefs = this.selectorPrefs()
    const cfg = obj(prefs, 'config')
    cfg[configId] = value
    prefs['config'] = cfg
    AppPrefs.set(`selectors.${this.agentType}`, JSON.stringify(prefs))
    if (this.options !== null) {
      const c = this.options.configs.find((x) => x.id === configId)
      if (c !== undefined) {
        c.current = value
      }
      this.version++
    }
    if (this.connectionId !== null) {
      try {
        await this.api.setConfigOption(this.connectionId, configId, value)
      } catch (e) {
        this.error = errorText(e)
      }
    }
  }

  removeQueued(i: number): void {
    this.queued = this.queued.filter((_: string, j: number) => j !== i)
  }
}

class SessionSocketListener implements EventSocketListener {
  private owner: SessionController
  private done: (ok: boolean) => void

  constructor(owner: SessionController, done: (ok: boolean) => void) {
    this.owner = owner
    this.done = done
  }

  onReady(): void {
    this.done(true)
  }

  onFrame(type: string, frame: JObj): void {
    this.owner.handleFrame(type, frame)
  }

  onChannel(channel: string, payload: JObj): void {
  }

  onClosed(reason: string): void {
    this.done(false)
    this.owner.handleClosed(reason)
  }
}
