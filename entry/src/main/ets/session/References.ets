import { Api } from '../net/Api'
import { asArr, asObj, str } from '../common/Json'
import { ConversationSummary, GitLogEntry } from '../model/Models'
import { L } from '../common/I18n'
import { agentName, statusLabel } from '../common/Agents'

/**
 * Composer references, matching the codeg web client (composer/reference-text.ts,
 * suggestion/adapters.ts). Each one is sent inline in the prompt text as a
 * Markdown link; the agent reads `codeg://session/<id>` through codeg's
 * `get_session_info` MCP tool.
 */
export enum RefKind {
  Agent = 'agent',
  Assistant = 'assistant',
  File = 'file',
  Session = 'session',
  Commit = 'commit'
}

export const REF_KINDS: RefKind[] = [RefKind.Agent, RefKind.Assistant, RefKind.File, RefKind.Session, RefKind.Commit]

export function refKindLabel(k: RefKind): string {
  switch (k) {
    case RefKind.Agent:
      return L('Agents', '智能体')
    case RefKind.Assistant:
      return L('Assistants', '助手')
    case RefKind.File:
      return L('Files', '文件')
    case RefKind.Session:
      return L('Sessions', '会话')
    default:
      return L('Commits', '提交')
  }
}

export class RefItem {
  kind: RefKind = RefKind.Session
  label: string = ''
  uri: string = ''
  detail: string = ''
  /** Agent type for the row icon (agents, assistants, sessions). */
  agent: string = ''
  keywords: string = ''

  /** Visible token in the draft; replaced by the Markdown link on send. */
  get token(): string {
    return this.kind === RefKind.Agent || this.kind === RefKind.Assistant ? `@${this.label}` : `@${this.label}`
  }

  get markdown(): string {
    const text = this.kind === RefKind.Agent || this.kind === RefKind.Assistant ? `@${this.label}` : this.label
    return `[${escapeMarkdownText(collapse(text))}](${escapeLinkDestination(this.uri)})`
  }
}

function collapse(s: string): string {
  return s.replace(new RegExp('\\s*[\\r\\n]+\\s*', 'g'), ' ')
}

export function escapeMarkdownText(s: string): string {
  return s.replace(new RegExp('([\\\\`*_~\\[\\]()<>])', 'g'), '\\$1')
}

export function escapeLinkDestination(uri: string): string {
  return new RegExp('[\\s()<>\\\\]').test(uri) ? `<${uri.replace(new RegExp('>', 'g'), '%3E')}>` : uri
}

/** `file://` URI the way the web's buildFileUri writes it. */
export function buildFileUri(absolutePath: string): string {
  const n = absolutePath.replace(new RegExp('\\\\', 'g'), '/')
  if (n.startsWith('//')) {
    return `file://${n.substring(2).split('/').map((p: string) => encodeURIComponent(p)).join('/')}`
  }
  const enc = n.split('/').map((p: string) => encodeURIComponent(p)).join('/')
  return n.startsWith('/') ? `file://${enc}` : `file:///${enc}`
}

/** Strips `[x](uri)` inside a title down to `x` (web formatConversationTitle). */
export function plainTitle(title: string): string {
  return title.replace(new RegExp('\\[([^\\]]*)\\]\\([^)]*\\)', 'g'), '$1').trim()
}

export function sessionRef(c: ConversationSummary): RefItem {
  const r = new RefItem()
  r.kind = RefKind.Session
  const t = plainTitle(c.title ?? '')
  r.label = t.length > 0 ? t : `#${c.id}`
  r.uri = `codeg://session/${c.id}`
  r.detail = (c.gitBranch ?? '').length > 0 ? (c.gitBranch ?? '') : statusLabel(c.status)
  r.agent = c.agentType
  r.keywords = `${r.label} ${c.agentType} ${agentName(c.agentType)} ${c.id}`
  return r
}

export function agentRef(agentType: string, name: string, description: string): RefItem {
  const r = new RefItem()
  r.kind = RefKind.Agent
  r.label = name.length > 0 ? name : agentName(agentType)
  r.uri = `codeg://agent/${agentType}`
  r.detail = description
  r.agent = agentType
  r.keywords = `${r.label} ${agentType}`
  return r
}

export function commitRef(repoPath: string, e: GitLogEntry): RefItem {
  const r = new RefItem()
  r.kind = RefKind.Commit
  r.label = e.hash
  r.uri = `codeg://commit/${encodeURIComponent(repoPath)}@${e.fullHash}`
  r.detail = e.message.split('\n')[0]
  r.keywords = `${e.hash} ${e.fullHash} ${e.message} ${e.author}`
  return r
}

export const MAX_PER_KIND = 50

export function matches(r: RefItem, query: string): boolean {
  const q = query.trim().toLowerCase()
  if (q.length === 0) {
    return true
  }
  return r.label.toLowerCase().includes(q) || r.keywords.toLowerCase().includes(q) ||
    r.detail.toLowerCase().includes(q) || r.uri.toLowerCase().includes(q)
}

export async function searchFiles(api: Api, root: string, query: string): Promise<RefItem[]> {
  const list = asArr(await api.c.call('search_workspace_files', { 'path': root, 'query': query, 'limit': MAX_PER_KIND + 1 }))
  const base = root.endsWith('/') ? root : `${root}/`
  return list.map((v: Object) => {
    const o = asObj(v)
    const r = new RefItem()
    r.kind = RefKind.File
    r.label = str(o, 'name')
    const rel = str(o, 'path')
    r.uri = buildFileUri(base + rel)
    r.detail = rel
    r.keywords = rel
    return r
  })
}

export async function listAssistants(api: Api): Promise<RefItem[]> {
  try {
    const list = asArr(await api.c.call('assistant_list'))
    return list.map((v: Object) => {
      const o = asObj(v)
      const r = new RefItem()
      r.kind = RefKind.Assistant
      r.label = str(o, 'name')
      r.uri = `codeg://assistant/${str(o, 'id')}`
      r.agent = str(o, 'agent_type', str(o, 'agentType'))
      r.detail = str(o, 'description', agentName(r.agent))
      r.keywords = `${r.label} ${r.agent}`
      return r
    }).filter((r: RefItem) => new RegExp('^codeg://assistant/[1-9]\\d{0,9}$').test(r.uri))
  } catch (e) {
    return []
  }
}

/**
 * Where an `@` mention is being typed: the query after `@` up to the caret.
 * Like the web, `@` counts only at the start, after whitespace, or after CJK
 * text/punctuation, so e-mail addresses don't open the panel.
 */
export class MentionAt {
  start: number = -1
  query: string = ''
}

export function mentionAt(text: string, caret: number): MentionAt {
  const out = new MentionAt()
  const end = Math.min(caret, text.length)
  for (let i = end - 1; i >= 0 && end - i <= 64; i--) {
    const ch = text[i]
    if (ch === '@') {
      const prev = i > 0 ? text[i - 1] : ''
      if (prev === '' || new RegExp('[\\s\\u3000-\\u303f\\u3040-\\u30ff\\u3400-\\u9fff\\uff00-\\uffef·゠・ー]').test(prev)) {
        out.start = i
        out.query = text.substring(i + 1, end)
      }
      return out
    }
    if (new RegExp('\\s').test(ch)) {
      return out
    }
  }
  return out
}

/** Replaces each still-present token with its Markdown link. */
export function expandRefs(text: string, refs: RefItem[]): string {
  // Claim each ref's first unclaimed occurrence, then splice left to right.
  const hits: number[][] = []
  const claimed: number[][] = []
  refs.forEach((r: RefItem, idx: number) => {
    let from = 0
    for (;;) {
      const i = text.indexOf(r.token, from)
      if (i < 0) {
        return
      }
      const clash = claimed.some((c: number[]) => i < c[1] && i + r.token.length > c[0])
      if (!clash) {
        claimed.push([i, i + r.token.length])
        hits.push([i, idx])
        return
      }
      from = i + 1
    }
  })
  hits.sort((a: number[], b: number[]) => a[0] - b[0])
  let out = ''
  let pos = 0
  for (const h of hits) {
    const r = refs[h[1]]
    out += text.substring(pos, h[0]) + r.markdown
    pos = h[0] + r.token.length
  }
  return out + text.substring(pos)
}

export function refIconForUri(uri: string): string {
  const u = uri.toLowerCase()
  if (u.startsWith('codeg://session/')) {
    return 'message'
  }
  if (u.startsWith('codeg://agent/')) {
    return 'person'
  }
  if (u.startsWith('codeg://assistant/')) {
    return 'person_2'
  }
  if (u.startsWith('codeg://commit/')) {
    return 'rectangle_split_3x1'
  }
  if (u.startsWith('file:')) {
    return 'doc'
  }
  return 'link'
}

/** Tiny pub/sub used by "Add to current session" in the session list. */
export class RefBus {
  private static listeners: Array<(r: RefItem) => void> = []

  static on(f: (r: RefItem) => void): void {
    RefBus.listeners.push(f)
  }

  static off(f: (r: RefItem) => void): void {
    RefBus.listeners = RefBus.listeners.filter((x: (r: RefItem) => void) => x !== f)
  }

  static emit(r: RefItem): void {
    RefBus.listeners.forEach((f: (r: RefItem) => void) => f(r))
  }
}

export class TextSeg {
  text: string = ''
  /** Set for a `codeg:` reference; rendered as a badge. */
  href: string = ''
}

/** Splits user text into plain runs and `[label](codeg:…)` reference badges. */
export function refSegments(text: string): TextSeg[] {
  const out: TextSeg[] = []
  const re = new RegExp('\\[((?:\\\\.|[^\\]\\\\])*)\\]\\((<[^>]*>|[^)\\s]+)\\)', 'g')
  let last = 0
  let m: RegExpExecArray | null = re.exec(text)
  while (m !== null) {
    let href = m[2]
    if (href.startsWith('<') && href.endsWith('>')) {
      href = href.substring(1, href.length - 1)
    }
    if (href.toLowerCase().startsWith('codeg:') && !href.toLowerCase().startsWith('codeg://embedded/')) {
      if (m.index > last) {
        const t = new TextSeg()
        t.text = text.substring(last, m.index)
        out.push(t)
      }
      const r = new TextSeg()
      const label = m[1].replace(new RegExp('\\\\(.)', 'g'), '$1')
      r.text = label.length > 0 ? label : href
      r.href = href
      out.push(r)
      last = m.index + m[0].length
    }
    m = re.exec(text)
  }
  if (last < text.length) {
    const t = new TextSeg()
    t.text = text.substring(last)
    out.push(t)
  }
  return out
}
