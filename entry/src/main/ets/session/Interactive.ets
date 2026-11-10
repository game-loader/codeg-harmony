import { JObj, arr, asObj, bool, num, obj, str } from '../common/Json'
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
}

export class ConfigOption {
  id: string = ''
  name: string = ''
  type: string = 'select'
  current: string = ''
  choices: ConfigChoice[] = []
}

export class AgentOptions {
  currentMode: string = ''
  modes: ModeOption[] = []
  configs: ConfigOption[] = []
  commands: string[] = []
  commandDescriptions: Map<string, string> = new Map()

  static from(o: JObj): AgentOptions {
    const a = new AgentOptions()
    const modes = obj(o, 'modes')
    a.currentMode = str(modes, 'current_mode_id', str(o, 'current_mode'))
    for (const m of arr(modes, 'available_modes')) {
      const mo = asObj(m)
      const mm = new ModeOption()
      mm.id = str(mo, 'id')
      mm.name = str(mo, 'name', mm.id)
      mm.description = str(mo, 'description')
      a.modes.push(mm)
    }
    for (const c of arr(o, 'config_options')) {
      const co = asObj(c)
      const cfg = new ConfigOption()
      cfg.id = str(co, 'id')
      cfg.name = str(co, 'name', cfg.id)
      cfg.type = str(co, 'type', 'select')
      cfg.current = str(co, 'current_value')
      const pushChoice = (v: Object) => {
        const vo = asObj(v)
        const ch = new ConfigChoice()
        ch.value = str(vo, 'value', str(vo, 'id'))
        ch.name = str(vo, 'name', ch.value)
        cfg.choices.push(ch)
      }
      arr(co, 'options').forEach(pushChoice)
      for (const g of arr(co, 'groups')) {
        arr(asObj(g), 'options').forEach(pushChoice)
      }
      a.configs.push(cfg)
    }
    for (const c of arr(o, 'available_commands')) {
      const co = asObj(c)
      const n = str(co, 'name')
      if (n.length > 0) {
        a.commands.push(n)
        a.commandDescriptions.set(n, str(co, 'description'))
      }
    }
    return a
  }
}
