import { JObj, arr, asObj, bool, has, obj, parseJson, pretty, str } from '../common/Json'
import { ContentBlock, MessageTurn } from '../model/Models'
import { FileDiff, diffFromStrings, parseUnifiedDiff } from './Diff'

export class PlanEntry {
  content: string = ''
  priority: string = ''
  status: string = 'pending'

  static from(v: Object): PlanEntry {
    const o = asObj(v)
    const p = new PlanEntry()
    p.content = str(o, 'content')
    p.priority = str(o, 'priority')
    const s = str(o, 'status', 'pending')
    p.status = s === 'done' ? 'completed' : (s === 'running' || s === 'active') ? 'in_progress' : s
    return p
  }
}

export class ImageRef {
  data: string = ''
  mimeType: string = 'image/png'
}

/** A tool call merged from live ACP events or persisted tool_use + tool_result blocks. */
@ObservedV2
export class ToolCall {
  id: string = ''
  @Trace name: string = ''
  @Trace kind: string = ''
  @Trace status: string = 'pending'
  @Trace input: string = ''
  @Trace output: string = ''
  @Trace content: string = ''
  @Trace isError: boolean = false
  @Trace subText: string = ''
  meta: JObj = {} as JObj

  get category(): string {
    const k = this.kind.toLowerCase()
    const n = this.name.toLowerCase().replace(new RegExp('^mcp__\\w+__'), '')
    if (n.includes('todowrite') || n === 'todo_write' || n === 'update_plan') {
      return 'todo'
    }
    if (n === 'task' || n === 'agent' || n.includes('delegate') || has(this.meta, 'codeg.delegation')) {
      return 'agent'
    }
    if (k === 'edit' || k === 'write' || k === 'delete' || k === 'move' ||
      n.startsWith('edit') || n.startsWith('write') || n.includes('multiedit') || n.includes('apply_patch') ||
      n.includes('str_replace') || n.includes('create_file')) {
      return 'edit'
    }
    if (k === 'read' || n === 'read' || n.startsWith('read') || n === 'view' || n === 'ls') {
      return 'read'
    }
    if (k === 'search' || n.includes('grep') || n.includes('glob') || n.includes('search') && !n.includes('web')) {
      return 'search'
    }
    if (k === 'execute' || k === 'command' || n === 'bash' || n.includes('shell') || n.includes('exec') ||
      n.includes('terminal') || n === 'command') {
      return 'execute'
    }
    if (k === 'fetch' || n.includes('web') || n.includes('fetch')) {
      return 'web'
    }
    if (k === 'think' || n.includes('exitplanmode') || n.includes('plan')) {
      return 'plan'
    }
    return 'other'
  }

  get inputObj(): JObj {
    try {
      return asObj(parseJson(this.input))
    } catch (e) {
      return {} as JObj
    }
  }

  /** One-line summary under the tool title: file, command, pattern or URL. */
  get detail(): string {
    const o = this.inputObj
    const keys = ['file_path', 'path', 'filePath', 'command', 'cmd', 'pattern', 'query', 'url', 'description', 'prompt']
    for (const k of keys) {
      const v = o[k]
      if (typeof v === 'string' && (v as string).length > 0) {
        return (v as string).split('\n')[0]
      }
      if (Array.isArray(v) && k === 'command') {
        return (v as Object[]).map((x: Object) => String(x)).join(' ')
      }
    }
    return ''
  }

  get diffs(): FileDiff[] {
    if (this.content.length > 0 && (this.content.includes('\n+') || this.content.includes('\n-') ||
      this.content.startsWith('@@') || this.content.startsWith('---'))) {
      const d = parseUnifiedDiff(this.content)
      if (d.length > 0) {
        return d
      }
    }
    const o = this.inputObj
    const path = str(o, 'file_path', str(o, 'path'))
    if (has(o, 'old_string') || has(o, 'new_string')) {
      return [diffFromStrings(path, str(o, 'old_string'), str(o, 'new_string'))]
    }
    if (has(o, 'old_str') || has(o, 'new_str')) {
      return [diffFromStrings(path, str(o, 'old_str'), str(o, 'new_str'))]
    }
    if (has(o, 'edits')) {
      const out: FileDiff[] = []
      for (const e of arr(o, 'edits')) {
        const eo = asObj(e)
        out.push(diffFromStrings(path, str(eo, 'old_string'), str(eo, 'new_string')))
      }
      return out
    }
    if (this.category === 'edit' && has(o, 'content') && path.length > 0) {
      return [diffFromStrings(path, '', str(o, 'content'))]
    }
    const patch = str(o, 'patch', str(o, 'input'))
    if (patch.includes('\n+') || patch.includes('*** Begin Patch')) {
      return parseUnifiedDiff(patch.replace(new RegExp('^\\*\\*\\* (Update|Add) File: (.+)$', 'gm'), '+++ b/$2'))
    }
    return []
  }

  get todos(): PlanEntry[] {
    const o = this.inputObj
    const list = has(o, 'todos') ? arr(o, 'todos') : arr(o, 'plan')
    return list.map((v: Object) => {
      const p = PlanEntry.from(v)
      if (p.content.length === 0) {
        p.content = str(asObj(v), 'step', str(asObj(v), 'activeForm'))
      }
      return p
    })
  }
}

export enum ItemKind {
  User = 'user',
  Text = 'text',
  Thinking = 'thinking',
  Tool = 'tool',
  Plan = 'plan',
  Image = 'image',
  Error = 'error',
  Notice = 'notice',
  Footer = 'footer'
}

@ObservedV2
export class TItem {
  id: string
  kind: ItemKind
  @Trace text: string = ''
  @Trace tool: ToolCall | null = null
  @Trace plan: PlanEntry[] = []
  @Trace images: ImageRef[] = []
  @Trace live: boolean = false
  @Trace pending: boolean = false
  ts: number = 0

  constructor(id: string, kind: ItemKind) {
    this.id = id
    this.kind = kind
  }
}

/** Flattens persisted turns into transcript items. */
export function itemsFromTurns(turns: MessageTurn[]): TItem[] {
  const out: TItem[] = []
  for (const turn of turns) {
    if (turn.role === 'user') {
      const it = new TItem(`u-${turn.id}`, ItemKind.User)
      const texts: string[] = []
      for (const b of turn.blocks) {
        if (b.type === 'text') {
          texts.push(b.text)
        } else if (b.type === 'image' && b.data.length > 0) {
          const im = new ImageRef()
          im.data = b.data
          im.mimeType = b.mimeType.length > 0 ? b.mimeType : 'image/png'
          it.images.push(im)
        }
      }
      it.text = texts.join('\n\n')
      it.ts = turn.timestamp
      out.push(it)
      continue
    }
    const tools: Map<string, ToolCall> = new Map()
    let idx = 0
    for (const b of turn.blocks) {
      const id = `${turn.id}-${idx++}`
      appendBlock(out, tools, b, id)
    }
    const footer = new TItem(`f-${turn.id}`, ItemKind.Footer)
    const parts: string[] = []
    if (turn.model !== undefined) {
      parts.push(turn.model)
    }
    if (turn.usage !== undefined) {
      parts.push(`↑${compact(turn.usage.input + turn.usage.cacheRead + turn.usage.cacheWrite)} ↓${compact(turn.usage.output)}`)
    }
    if (turn.durationMs !== undefined) {
      parts.push(`${(turn.durationMs / 1000).toFixed(1)}s`)
    }
    if (parts.length > 0) {
      footer.text = parts.join(' · ')
      footer.ts = turn.timestamp
      out.push(footer)
    }
  }
  return out
}

function compact(n: number): string {
  return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`
}

function appendBlock(out: TItem[], tools: Map<string, ToolCall>, b: ContentBlock, id: string): void {
  const last = out.length > 0 ? out[out.length - 1] : null
  switch (b.type) {
    case 'text': {
      if (b.text.trim().length === 0) {
        return
      }
      if (last !== null && last.kind === ItemKind.Text) {
        last.text += b.text
        return
      }
      const it = new TItem(id, ItemKind.Text)
      it.text = b.text
      out.push(it)
      return
    }
    case 'thinking': {
      if (b.text.trim().length === 0) {
        return
      }
      if (last !== null && last.kind === ItemKind.Thinking) {
        last.text += b.text
        return
      }
      const it = new TItem(id, ItemKind.Thinking)
      it.text = b.text
      out.push(it)
      return
    }
    case 'tool_use': {
      const tc = new ToolCall()
      tc.id = b.toolUseId
      tc.name = b.toolName
      tc.input = b.inputPreview
      tc.status = b.status.length > 0 ? b.status : 'completed'
      tc.meta = b.meta
      tools.set(tc.id, tc)
      const it = new TItem(id, ItemKind.Tool)
      it.tool = tc
      out.push(it)
      return
    }
    case 'tool_result': {
      const tc = tools.get(b.toolUseId)
      if (tc !== undefined) {
        tc.output = b.outputPreview
        tc.isError = b.isError
        if (b.isError) {
          tc.status = 'failed'
        }
      }
      return
    }
    case 'image':
    case 'image_generation': {
      if (b.data.length === 0) {
        return
      }
      const it = new TItem(id, ItemKind.Image)
      const im = new ImageRef()
      im.data = b.data
      im.mimeType = b.mimeType.length > 0 ? b.mimeType : 'image/png'
      it.images = [im]
      it.text = b.text
      out.push(it)
      return
    }
    case 'turn_error': {
      const it = new TItem(id, ItemKind.Error)
      it.text = b.text
      out.push(it)
      return
    }
    default:
      return
  }
}

/** Builds a ToolCall from a live `tool_call` event or a snapshot `active_tool_calls` entry. */
export function toolFromEvent(o: JObj): ToolCall {
  const tc = new ToolCall()
  tc.id = str(o, 'tool_call_id', str(o, 'id'))
  tc.name = str(o, 'title', str(o, 'label'))
  tc.kind = str(o, 'kind')
  tc.status = str(o, 'status', 'pending')
  tc.content = typeof o['content'] === 'string' ? str(o, 'content') : contentToText(o['content'])
  tc.input = has(o, 'raw_input') ? pretty(o['raw_input']) : pretty(o['input'])
  if (has(o, 'raw_output')) {
    tc.output = pretty(o['raw_output'])
  } else if (has(o, 'output')) {
    const out = obj(o, 'output')
    tc.output = str(out, 'content', str(out, 'message', pretty(out['value'])))
    tc.isError = str(out, 'kind') === 'error'
  }
  tc.meta = obj(o, 'meta')
  return tc
}

export function applyToolUpdate(tc: ToolCall, o: JObj): void {
  if (has(o, 'title')) {
    tc.name = str(o, 'title')
  }
  if (has(o, 'status')) {
    tc.status = str(o, 'status')
    tc.isError = tc.status === 'failed'
  }
  if (has(o, 'content')) {
    tc.content = typeof o['content'] === 'string' ? str(o, 'content') : contentToText(o['content'])
  }
  if (has(o, 'raw_input')) {
    tc.input = pretty(o['raw_input'])
  }
  if (has(o, 'raw_output')) {
    const v = pretty(o['raw_output'])
    tc.output = bool(o, 'raw_output_append') ? tc.output + v : v
  }
  if (has(o, 'meta')) {
    tc.meta = obj(o, 'meta')
  }
}

/** ACP tool content arrays: text blocks and {type:"diff"} entries become a unified diff. */
function contentToText(v: Object | null | undefined): string {
  if (v === null || v === undefined) {
    return ''
  }
  if (!Array.isArray(v)) {
    return pretty(v)
  }
  const parts: string[] = []
  for (const c of v as Object[]) {
    const o = asObj(c)
    const t = str(o, 'type')
    if (t === 'diff') {
      const d = diffFromStrings(str(o, 'path'), str(o, 'old_text', str(o, 'oldText')), str(o, 'new_text', str(o, 'newText')))
      const lines: string[] = [`--- a/${d.path}`, `+++ b/${d.path}`, '@@ -1 +1 @@']
      for (const l of d.lines) {
        lines.push(`${l.kind}${l.text}`)
      }
      parts.push(lines.join('\n'))
    } else {
      const inner = obj(o, 'content')
      const txt = str(o, 'text', str(inner, 'text'))
      if (txt.length > 0) {
        parts.push(txt)
      }
    }
  }
  return parts.join('\n')
}

/** A user turn's text with attachment links `[name](file:///…)` pulled out as chips. */
export class UserText {
  text: string = ''
  files: string[] = []
}

export function splitUserResources(text: string): UserText {
  const r = new UserText()
  const re = new RegExp('\\[([^\\]]+)\\]\\((file://[^)]+)\\)', 'g')
  r.text = text.replace(re, (m: string, name: string) => {
    r.files.push(name)
    return ''
  }).trim()
  return r
}
