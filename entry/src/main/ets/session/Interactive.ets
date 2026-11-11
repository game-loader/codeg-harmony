import { JObj, arr, asObj, bool, isObj, num, obj, str } from '../common/Json'
import { L } from '../common/I18n'
import { FileDiff, diffFromStrings, parseUnifiedDiff } from './Diff'

export class PermissionOption {
  id: string = ''
  name: string = ''
  kind: string = ''

  get isReject(): boolean {
    return this.kind.startsWith('reject')
  }
}

export class PermissionRequest {
  requestId: string = ''
  title: string = ''
  kind: string = ''
  command: string = ''
  planMarkdown: string = ''
  diffs: FileDiff[] = []
  options: PermissionOption[] = []
  queued: number = 0

  static from(o: JObj): PermissionRequest {
    const p = new PermissionRequest()
    p.requestId = str(o, 'request_id')
    p.queued = num(o, 'queued')
    const tc = obj(o, 'tool_call')
    p.title = str(tc, 'title', str(tc, 'name'))
    p.kind = str(tc, 'kind')
    const raw = obj(tc, 'raw_input')
    p.command = str(raw, 'command', str(raw, 'url', str(raw, 'query', str(raw, 'file_path'))))
    p.planMarkdown = str(raw, 'plan')
    for (const c of arr(tc, 'content')) {
      const co = asObj(c)
      if (str(co, 'type') === 'diff') {
        p.diffs.push(diffFromStrings(str(co, 'path'), str(co, 'old_text', str(co, 'oldText')),
          str(co, 'new_text', str(co, 'newText'))))
      }
    }
    for (const k of ['patch', 'diff', 'unified_diff', 'unifiedDiff']) {
      const v = str(raw, k)
      if (v.length > 0) {
        p.diffs = p.diffs.concat(parseUnifiedDiff(v))
      }
    }
    if (p.diffs.length === 0 && (raw['old_string'] !== undefined || raw['new_string'] !== undefined)) {
      p.diffs.push(diffFromStrings(str(raw, 'file_path'), str(raw, 'old_string'), str(raw, 'new_string')))
    }
    for (const v of arr(o, 'options')) {
      const oo = asObj(v)
      const op = new PermissionOption()
      op.id = str(oo, 'option_id', str(oo, 'optionId'))
      op.name = str(oo, 'name', op.id)
      op.kind = str(oo, 'kind')
      p.options.push(op)
    }
    return p
  }
}

export class QuestionOption {
  label: string = ''
  description: string = ''
}

export class Question {
  id: string = ''
  question: string = ''
  header: string = ''
  multiSelect: boolean = false
  isSecret: boolean = false
  options: QuestionOption[] = []
}

export class QuestionRequest {
  questionId: string = ''
  questions: Question[] = []

  static from(o: JObj): QuestionRequest {
    const q = new QuestionRequest()
    q.questionId = str(o, 'question_id')
    for (const v of arr(o, 'questions')) {
      const qo = asObj(v)
      const qq = new Question()
      qq.id = str(qo, 'id')
      qq.question = str(qo, 'question')
      qq.header = str(qo, 'header')
      qq.multiSelect = bool(qo, 'multi_select')
      qq.isSecret = bool(qo, 'is_secret')
      for (const ov of arr(qo, 'options')) {
        const op = new QuestionOption()
        op.label = str(asObj(ov), 'label')
        op.description = str(asObj(ov), 'description')
        qq.options.push(op)
      }
      q.questions.push(qq)
    }
    return q
  }
}

export class PlanApproval {
  approvalId: string = ''
  markdown: string = ''

  static from(o: JObj): PlanApproval {
    const p = new PlanApproval()
    p.approvalId = str(o, 'approval_id')
    p.markdown = str(o, 'plan_markdown')
    return p
  }
}

export class SessionFailure {
  id: string = ''
  revision: number = 0
  category: string = ''
  severity: string = 'error'
  title: string = ''
  details: string = ''
  resolved: boolean = false

  static from(o: JObj): SessionFailure {
    const f = new SessionFailure()
    f.id = str(o, 'id')
    f.revision = num(o, 'revision')
    f.category = str(o, 'category', 'unknown')
    f.severity = str(o, 'severity', 'error')
    f.title = str(o, 'title')
    f.details = str(o, 'details')
    f.resolved = bool(o, 'resolved')
    return f
  }
}

export class ModeOption {
  id: string = ''
  name: string = ''
  description: string = ''
}

export class ConfigChoice {
  value: string = ''
  name: string = ''
  description: string = ''
  /** Heading the choice is listed under; empty when the agent sends a flat list. */
  group: string = ''

  static of(value: string, name: string): ConfigChoice {
    const c = new ConfigChoice()
    c.value = value
    c.name = name
    return c
  }

  static from(v: Object, group: string): ConfigChoice {
    const o = asObj(v)
    const c = ConfigChoice.of(str(o, 'value', str(o, 'id')), '')
    c.name = str(o, 'name', c.value)
    c.description = str(o, 'description')
    c.group = group
    return c
  }
}

/** Row key for the session mode, which is set through its own server command. */
export const MODE_KEY: string = '__mode__'

/** One selectable setting of an agent session: model, effort, permission mode and so on. */
export class ConfigOption {
  id: string = ''
  name: string = ''
  description: string = ''
  category: string = ''
  /** `select`, `boolean`, or a kind a newer server adds (not listed). */
  type: string = 'select'
  current: string = ''
  choices: ConfigChoice[] = []

  /**
   * The server nests the control under `kind`:
   * `{ id, name, category, kind: { type, current_value, options, groups } }`.
   */
  static from(v: Object): ConfigOption {
    const o = asObj(v)
    const kind = isObj(o['kind']) ? obj(o, 'kind') : o
    const c = new ConfigOption()
    c.id = str(o, 'id')
    c.name = str(o, 'name', c.id)
    c.description = str(o, 'description')
    c.category = str(o, 'category')
    c.type = str(kind, 'type', 'select')
    if (c.type === 'boolean') {
      // The server carries an on/off option as the strings "true" / "false".
      c.current = bool(kind, 'current_value') ? 'true' : 'false'
      c.choices = [ConfigChoice.of('true', L('On', '开')), ConfigChoice.of('false', L('Off', '关'))]
      return c
    }
    c.current = str(kind, 'current_value')
    // A grouped select repeats every choice in `options`, so list each one once.
    const groups = arr(kind, 'groups')
    if (groups.length > 0) {
      for (const g of groups) {
        const go = asObj(g)
        const title = str(go, 'name', str(go, 'group'))
        for (const ch of arr(go, 'options')) {
          c.choices.push(ConfigChoice.from(ch, title))
        }
      }
    } else {
      for (const ch of arr(kind, 'options')) {
        c.choices.push(ConfigChoice.from(ch, ''))
      }
    }
    return c
  }

  has(value: string): boolean {
    return this.choices.some((c: ConfigChoice) => c.value === value)
  }

  get usable(): boolean {
    return this.type === 'boolean' || this.type === 'select' && this.choices.length > 0
  }

  get currentName(): string {
    const ch = this.choices.find((c: ConfigChoice) => c.value === this.current)
    return ch !== undefined ? ch.name : this.current
  }

  get currentDescription(): string {
    const ch = this.choices.find((c: ConfigChoice) => c.value === this.current)
    return ch !== undefined ? ch.description : ''
  }

  /** Group headings in order; empty when the choices are a flat list. */
  get groupNames(): string[] {
    const out: string[] = []
    for (const c of this.choices) {
      if (c.group.length > 0 && !out.includes(c.group)) {
        out.push(c.group)
      }
    }
    return out
  }

  inGroup(group: string): ConfigChoice[] {
    return this.choices.filter((c: ConfigChoice) => c.group === group)
  }

  withCurrent(value: string): ConfigOption {
    const c = new ConfigOption()
    c.id = this.id
    c.name = this.name
    c.description = this.description
    c.category = this.category
    c.type = this.type
    c.current = value
    c.choices = this.choices
    return c
  }
}

/**
 * The mode and options of an agent, from an option catalog
 * (`acp_describe_agent_options`) or a live session snapshot. Treated as
 * immutable once shown: a change produces a new object, so views re-render.
 */
export class AgentOptions {
  currentMode: string = ''
  modes: ModeOption[] = []
  configs: ConfigOption[] = []
  commands: string[] = []
  commandDescriptions: Map<string, string> = new Map()
  /** False while a starting connection has not reported its selectors yet. */
  ready: boolean = true

  static from(o: JObj): AgentOptions {
    const a = new AgentOptions()
    a.setModes(obj(o, 'modes'))
    if (a.currentMode.length === 0) {
      a.currentMode = str(o, 'current_mode')
    }
    a.setConfigs(arr(o, 'config_options'))
    a.setCommands(arr(o, 'available_commands'))
    a.ready = bool(o, 'selectors_ready', true)
    return a
  }

  setModes(state: JObj): void {
    const list: ModeOption[] = []
    for (const m of arr(state, 'available_modes')) {
      const mo = asObj(m)
      const mm = new ModeOption()
      mm.id = str(mo, 'id')
      mm.name = str(mo, 'name', mm.id)
      mm.description = str(mo, 'description')
      list.push(mm)
    }
    this.modes = list
    this.currentMode = str(state, 'current_mode_id')
  }

  setConfigs(list: Object[]): void {
    this.configs = list.map((v: Object) => ConfigOption.from(v))
  }

  setCommands(list: Object[]): void {
    const names: string[] = []
    const descriptions: Map<string, string> = new Map()
    for (const c of list) {
      const co = asObj(c)
      const n = str(co, 'name')
      if (n.length > 0) {
        names.push(n)
        descriptions.set(n, str(co, 'description'))
      }
    }
    this.commands = names
    this.commandDescriptions = descriptions
  }

  copy(): AgentOptions {
    const a = new AgentOptions()
    a.currentMode = this.currentMode
    a.modes = this.modes
    a.configs = this.configs
    a.commands = this.commands
    a.commandDescriptions = this.commandDescriptions
    a.ready = this.ready
    return a
  }

  /**
   * An agent that publishes config options represents its mode among them
   * (Claude Code and Codex call that option `mode`), so the mode list is shown
   * on its own only for agents without config options, as the web client does.
   */
  get showModes(): boolean {
    return this.modes.length > 0 && this.configs.length === 0
  }

  private modeRow(): ConfigOption {
    const r = new ConfigOption()
    r.id = MODE_KEY
    r.name = L('Mode', '模式')
    r.category = 'mode'
    r.current = this.currentMode
    r.choices = this.modes.map((m: ModeOption) => {
      const c = ConfigChoice.of(m.id, m.name)
      c.description = m.description
      return c
    })
    return r
  }

  /** What the options UI lists, in order. */
  get rows(): ConfigOption[] {
    const out: ConfigOption[] = []
    if (this.showModes) {
      out.push(this.modeRow())
    }
    for (const c of this.configs) {
      if (c.usable) {
        out.push(c)
      }
    }
    return out
  }

  row(key: string): ConfigOption | undefined {
    return this.rows.find((r: ConfigOption) => r.id === key)
  }

  valueOf(key: string): string {
    if (key === MODE_KEY) {
      return this.currentMode
    }
    const r = this.row(key)
    return r !== undefined ? r.current : ''
  }

  withValue(key: string, value: string): AgentOptions {
    const a = this.copy()
    if (key === MODE_KEY) {
      a.currentMode = value
    } else {
      a.configs = this.configs.map((c: ConfigOption) => c.id === key ? c.withCurrent(value) : c)
    }
    return a
  }

  private modelRow(rows: ConfigOption[]): ConfigOption | undefined {
    return rows.find((r: ConfigOption) => r.id === 'model') ?? rows.find((r: ConfigOption) => r.category === 'model')
  }

  private permissionRow(rows: ConfigOption[]): ConfigOption | undefined {
    return rows.find((r: ConfigOption) => r.id === MODE_KEY || r.id === 'mode') ??
    rows.find((r: ConfigOption) => r.category === 'mode')
  }

  /** The rows a compact view leads with: the model and the mode (else the first two). */
  get primaryRows(): ConfigOption[] {
    const rows = this.rows
    const ids: string[] = []
    const model = this.modelRow(rows)
    if (model !== undefined) {
      ids.push(model.id)
    }
    const mode = this.permissionRow(rows)
    if (mode !== undefined && !ids.includes(mode.id)) {
      ids.push(mode.id)
    }
    return ids.length > 0 ? rows.filter((r: ConfigOption) => ids.includes(r.id)) : rows.slice(0, 2)
  }

  get moreRows(): ConfigOption[] {
    const ids = this.primaryRows.map((r: ConfigOption) => r.id)
    return this.rows.filter((r: ConfigOption) => !ids.includes(r.id))
  }

  /** "Model · Mode" for the composer button; empty when the agent reports neither. */
  get summary(): string {
    const rows = this.rows
    const parts: string[] = []
    const model = this.modelRow(rows)
    if (model !== undefined && model.currentName.length > 0) {
      parts.push(model.currentName)
    }
    const mode = this.permissionRow(rows)
    if (mode !== undefined && mode !== model && mode.currentName.length > 0) {
      parts.push(mode.currentName)
    }
    return parts.join(' · ')
  }
}
