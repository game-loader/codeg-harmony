import { JObj, asObj, arr, bool, num, obj, optNum, optStr, parseDate, str, strArr, has } from '../common/Json'

export class FolderDetail {
  id: number = 0
  name: string = ''
  path: string = ''
  gitBranch?: string
  defaultAgentType?: string
  lastOpenedAt: number = 0
  sortOrder: number = 0
  color: string = ''
  parentId?: number
  kind: string = 'regular'
  alias?: string

  static from(v: Object): FolderDetail {
    const o = asObj(v)
    const f = new FolderDetail()
    f.id = num(o, 'id')
    f.name = str(o, 'name')
    f.path = str(o, 'path')
    f.gitBranch = optStr(o, 'git_branch')
    f.defaultAgentType = optStr(o, 'default_agent_type')
    f.lastOpenedAt = parseDate(str(o, 'last_opened_at'))
    f.sortOrder = num(o, 'sort_order')
    f.color = str(o, 'color')
    f.parentId = optNum(o, 'parent_id')
    f.kind = str(o, 'kind', 'regular')
    f.alias = optStr(o, 'alias')
    return f
  }

  get displayName(): string {
    if (this.alias !== undefined && this.alias.length > 0) {
      return `${this.alias} [ ${this.name} ]`
    }
    return this.name
  }

  get isWorktree(): boolean {
    return this.parentId !== undefined
  }

  get isChat(): boolean {
    return this.kind === 'chat'
  }
}

export class ConversationSummary {
  id: number = 0
  folderId: number = 0
  title?: string
  agentType: string = 'claude_code'
  status: string = 'in_progress'
  model?: string
  gitBranch?: string
  externalId?: string
  messageCount: number = 0
  createdAt: number = 0
  updatedAt: number = 0
  pinnedAt?: number
  tagIds: number[] = []

  static from(v: Object): ConversationSummary {
    const o = asObj(v)
    const c = new ConversationSummary()
    c.id = num(o, 'id')
    c.folderId = num(o, 'folder_id')
    c.title = optStr(o, 'title')
    c.agentType = str(o, 'agent_type', 'claude_code')
    c.status = str(o, 'status', 'in_progress')
    c.model = optStr(o, 'model')
    c.gitBranch = optStr(o, 'git_branch')
    c.externalId = optStr(o, 'external_id')
    c.messageCount = num(o, 'message_count')
    c.createdAt = parseDate(str(o, 'created_at'))
    c.updatedAt = parseDate(str(o, 'updated_at'))
    if (has(o, 'pinned_at')) {
      c.pinnedAt = parseDate(str(o, 'pinned_at'))
    }
    for (const t of arr(o, 'tag_ids')) {
      if (typeof t === 'number') {
        c.tagIds.push(t as number)
      }
    }
    return c
  }

  get displayTitle(): string {
    const t = this.title ?? ''
    return t.trim().length > 0 ? t : `#${this.id}`
  }
}

export class ContentBlock {
  type: string = 'text'
  text: string = ''
  mimeType: string = ''
  data: string = ''
  toolUseId: string = ''
  toolName: string = ''
  inputPreview: string = ''
  outputPreview: string = ''
  isError: boolean = false
  status: string = ''
  meta: JObj = {} as JObj

  static from(v: Object): ContentBlock {
    const o = asObj(v)
    const b = new ContentBlock()
    b.type = str(o, 'type', 'text')
    b.text = str(o, 'text', str(o, 'message', str(o, 'revised_prompt')))
    b.mimeType = str(o, 'mime_type')
    b.data = str(o, 'data')
    if (b.type === 'image_generation') {
      const img = obj(o, 'image')
      b.data = str(img, 'data')
      b.mimeType = str(img, 'mime_type', 'image/png')
    }
    b.toolUseId = str(o, 'tool_use_id')
    b.toolName = str(o, 'tool_name')
    b.inputPreview = str(o, 'input_preview')
    b.outputPreview = str(o, 'output_preview')
    b.isError = bool(o, 'is_error')
    b.status = str(o, 'status')
    b.meta = obj(o, 'meta')
    return b
  }
}

export class TurnUsage {
  input: number = 0
  output: number = 0
  cacheRead: number = 0
  cacheWrite: number = 0
}

export class MessageTurn {
  id: string = ''
  role: string = 'assistant'
  blocks: ContentBlock[] = []
  timestamp: number = 0
  usage?: TurnUsage
  durationMs?: number
  model?: string

  static from(v: Object): MessageTurn {
    const o = asObj(v)
    const t = new MessageTurn()
    t.id = str(o, 'id')
    t.role = str(o, 'role', 'assistant')
    t.blocks = arr(o, 'blocks').map((b: Object) => ContentBlock.from(b))
    t.timestamp = parseDate(str(o, 'timestamp'))
    if (has(o, 'usage')) {
      const u = obj(o, 'usage')
      const tu = new TurnUsage()
      tu.input = num(u, 'input_tokens')
      tu.output = num(u, 'output_tokens')
      tu.cacheRead = num(u, 'cache_read_input_tokens')
      tu.cacheWrite = num(u, 'cache_creation_input_tokens')
      t.usage = tu
    }
    t.durationMs = optNum(o, 'duration_ms')
    t.model = optStr(o, 'model')
    return t
  }
}

export class SessionStats {
  totalTokens: number = 0
  durationMs: number = 0
  contextUsed: number = 0
  contextMax: number = 0
  contextPercent: number = 0
}

export class ConversationDetail {
  summary: ConversationSummary = new ConversationSummary()
  turns: MessageTurn[] = []
  stats?: SessionStats

  static from(v: Object): ConversationDetail {
    const o = asObj(v)
    const d = new ConversationDetail()
    d.summary = ConversationSummary.from(o['summary'])
    d.turns = arr(o, 'turns').map((t: Object) => MessageTurn.from(t))
    if (has(o, 'session_stats')) {
      const s = obj(o, 'session_stats')
      const st = new SessionStats()
      st.totalTokens = num(s, 'total_tokens')
      st.durationMs = num(s, 'total_duration_ms')
      st.contextUsed = num(s, 'context_window_used_tokens')
      st.contextMax = num(s, 'context_window_max_tokens')
      st.contextPercent = num(s, 'context_window_usage_percent')
      d.stats = st
    }
    return d
  }
}

export class AgentInfo {
  agentType: string = ''
  name: string = ''
  description: string = ''
  available: boolean = false
  enabled: boolean = false
  sortOrder: number = 0
  installedVersion?: string
  distributionType?: string
  env: JObj = {} as JObj
  modelProviderId?: number

  static from(v: Object): AgentInfo {
    const o = asObj(v)
    const a = new AgentInfo()
    a.agentType = str(o, 'agent_type')
    a.name = str(o, 'name', a.agentType)
    a.description = str(o, 'description')
    a.available = bool(o, 'available')
    a.enabled = bool(o, 'enabled', true)
    a.sortOrder = num(o, 'sort_order')
    a.installedVersion = optStr(o, 'installed_version')
    a.distributionType = optStr(o, 'distribution_type')
    a.env = obj(o, 'env')
    a.modelProviderId = optNum(o, 'model_provider_id')
    return a
  }
}

export class DirEntry {
  name: string = ''
  path: string = ''
  isDir: boolean = true
  hasChildren: boolean = false
  size?: number

  static from(v: Object): DirEntry {
    const o = asObj(v)
    const e = new DirEntry()
    e.name = str(o, 'name')
    e.path = str(o, 'path')
    e.isDir = bool(o, 'isDir', bool(o, 'is_dir', true))
    e.hasChildren = bool(o, 'hasChildren', bool(o, 'has_children'))
    e.size = optNum(o, 'size')
    return e
  }
}

export class QuickMessage {
  id: number = 0
  title: string = ''
  content: string = ''
  sortOrder: number = 0

  static from(v: Object): QuickMessage {
    const o = asObj(v)
    const q = new QuickMessage()
    q.id = num(o, 'id')
    q.title = str(o, 'title')
    q.content = str(o, 'content')
    q.sortOrder = num(o, 'sort_order')
    return q
  }
}

export class ConversationTag {
  id: number = 0
  folderId?: number
  name: string = ''
  color: string = ''
  sortOrder: number = 0

  static from(v: Object): ConversationTag {
    const o = asObj(v)
    const t = new ConversationTag()
    t.id = num(o, 'id')
    t.folderId = optNum(o, 'folder_id')
    t.name = str(o, 'name')
    t.color = str(o, 'color')
    t.sortOrder = num(o, 'sort_order')
    return t
  }
}

export class GitStatusEntry {
  status: string = ''
  file: string = ''

  static from(v: Object): GitStatusEntry {
    const o = asObj(v)
    const g = new GitStatusEntry()
    g.status = str(o, 'status')
    g.file = str(o, 'file')
    return g
  }

  get path(): string {
    const i = this.file.indexOf(' -> ')
    return i >= 0 ? this.file.substring(i + 4) : this.file
  }
}

export class GitLogFile {
  path: string = ''
  status: string = ''
  additions: number = 0
  deletions: number = 0
}

export class GitLogEntry {
  hash: string = ''
  fullHash: string = ''
  author: string = ''
  date: number = 0
  message: string = ''
  pushed?: boolean
  files: GitLogFile[] = []

  static from(v: Object): GitLogEntry {
    const o = asObj(v)
    const e = new GitLogEntry()
    e.hash = str(o, 'hash')
    e.fullHash = str(o, 'full_hash', e.hash)
    e.author = str(o, 'author')
    e.date = parseDate(str(o, 'date'))
    e.message = str(o, 'message')
    if (has(o, 'pushed')) {
      e.pushed = bool(o, 'pushed')
    }
    for (const f of arr(o, 'files')) {
      const fo = asObj(f)
      const lf = new GitLogFile()
      lf.path = str(fo, 'path')
      lf.status = str(fo, 'status')
      lf.additions = num(fo, 'additions')
      lf.deletions = num(fo, 'deletions')
      e.files.push(lf)
    }
    return e
  }
}

export class GitBranches {
  local: string[] = []
  remote: string[] = []
  worktreeBranches: string[] = []

  static from(v: Object): GitBranches {
    const o = asObj(v)
    const b = new GitBranches()
    b.local = strArr(o, 'local')
    b.remote = strArr(o, 'remote')
    b.worktreeBranches = strArr(o, 'worktree_branches')
    return b
  }
}

export class GitWorktree {
  path: string = ''
  branch?: string
  head: string = ''
  isMain: boolean = false
  locked: boolean = false
  prunable: boolean = false

  static from(v: Object): GitWorktree {
    const o = asObj(v)
    const w = new GitWorktree()
    w.path = str(o, 'path')
    w.branch = optStr(o, 'branch')
    w.head = str(o, 'head', str(o, 'commit'))
    w.isMain = bool(o, 'is_main', bool(o, 'is_main_worktree'))
    // Server sends Option<String>: present (even empty) means set.
    w.locked = typeof o['locked'] === 'string' || bool(o, 'locked')
    w.prunable = typeof o['prunable'] === 'string' || bool(o, 'prunable')
    return w
  }
}

export class Machine {
  id: string = ''
  name: string = ''
  dnsName: string = ''
  addresses: string[] = []
  os: string = ''
  online?: boolean
  lastSeen?: string
  isSelf: boolean = false
  source: string = ''
  sshPort: number = 22
  sshUser?: string

  static from(v: Object): Machine {
    const o = asObj(v)
    const m = new Machine()
    m.id = str(o, 'id')
    m.name = str(o, 'name')
    m.dnsName = str(o, 'dns_name')
    m.addresses = strArr(o, 'addresses')
    m.os = str(o, 'os')
    if (has(o, 'online')) {
      m.online = bool(o, 'online')
    }
    m.lastSeen = optStr(o, 'last_seen')
    m.isSelf = bool(o, 'is_self')
    m.source = str(o, 'source')
    m.sshPort = num(o, 'ssh_port', 22)
    m.sshUser = optStr(o, 'ssh_user')
    return m
  }

  get isManual(): boolean {
    return this.source === 'manual'
  }
}

export class MachineMetric {
  label: string = ''
  value: string = ''
}

export class ExpertSkill {
  id: string = ''
  category: string = ''
  name: string = ''
  description: string = ''
}

export class SlashCommand {
  name: string = ''
  description: string = ''
  hint: string = ''
}
