import { isFileHref, isFilePathText, parseFileTarget } from '../session/FileRefs'

export enum MdKind {
  Para = 'p',
  Heading = 'h',
  Code = 'code',
  Quote = 'quote',
  List = 'list',
  Rule = 'hr',
  Table = 'table',
  Math = 'math'
}

export class MdListItem {
  text: string = ''
  level: number = 0
  ordered: boolean = false
  index: number = 1
  task: number = -1 // -1 none, 0 open, 1 done
}

export class MdBlock {
  kind: MdKind = MdKind.Para
  text: string = ''
  level: number = 0
  lang: string = ''
  items: MdListItem[] = []
  rows: string[][] = []
  align: string[] = []
  key: string = ''
}

export enum SpanKind {
  Text = 't',
  Bold = 'b',
  Italic = 'i',
  BoldItalic = 'bi',
  Strike = 's',
  Code = 'c',
  /** Inline code that is a path to a file; `href` holds the path. */
  CodeFile = 'cf',
  Link = 'l',
  File = 'f',
  Ref = 'r',
  Math = 'm'
}

export class MdSpan {
  kind: SpanKind = SpanKind.Text
  text: string = ''
  href: string = ''
}

const FENCE = new RegExp('^\\s{0,3}(`{3,}|~{3,})\\s*([^`\\s]*)')
const HEADING = new RegExp('^\\s{0,3}(#{1,6})\\s+(.*?)\\s*#*\\s*$')
const RULE = new RegExp('^\\s{0,3}([-*_])(\\s*\\1){2,}\\s*$')
const LIST = new RegExp('^(\\s*)([-*+]|\\d{1,9}[.)])\\s+(.*)$')
const TASK = new RegExp('^\\[([ xX])\\]\\s+(.*)$')
const TABLE_SEP = new RegExp('^\\s*\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)*\\|?\\s*$')

function isFenceClose(line: string, fence: string): boolean {
  const t = line.trim()
  if (t.length < fence.length || !t.startsWith(fence)) {
    return false
  }
  for (let k = 0; k < t.length; k++) {
    if (t[k] !== fence[0]) {
      return false
    }
  }
  return true
}

function splitRow(line: string): string[] {
  let s = line.trim()
  if (s.startsWith('|')) {
    s = s.substring(1)
  }
  if (s.endsWith('|') && !s.endsWith('\\|')) {
    s = s.substring(0, s.length - 1)
  }
  // Split on unescaped pipes without regex lookbehind.
  const cells: string[] = []
  let cur = ''
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '\\' && s[i + 1] === '|') {
      cur += '|'
      i++
    } else if (s[i] === '|') {
      cells.push(cur.trim())
      cur = ''
    } else {
      cur += s[i]
    }
  }
  cells.push(cur.trim())
  return cells
}

/** Block-level markdown parser covering what agents emit in practice. */
export function parseMarkdown(src: string): MdBlock[] {
  const lines = src.replace(new RegExp('\\r\\n', 'g'), '\n').split('\n')
  const out: MdBlock[] = []
  let i = 0
  let para: string[] = []
  const flush = () => {
    if (para.length > 0) {
      const b = new MdBlock()
      b.kind = MdKind.Para
      b.text = para.join('\n')
      out.push(b)
      para = []
    }
  }
  while (i < lines.length) {
    const line = lines[i]
    const fm = FENCE.exec(line)
    if (fm !== null) {
      flush()
      const fence = fm[1]
      const b = new MdBlock()
      b.kind = MdKind.Code
      b.lang = fm[2] ?? ''
      const body: string[] = []
      i++
      while (i < lines.length && !isFenceClose(lines[i], fence)) {
        body.push(lines[i])
        i++
      }
      i++
      b.text = body.join('\n')
      out.push(b)
      continue
    }
    const trimmed = line.trim()
    if (trimmed.startsWith('$$') || trimmed.startsWith('\\[')) {
      const close = trimmed.startsWith('$$') ? '$$' : '\\]'
      const rest = trimmed.substring(2)
      if (rest.endsWith(close) && rest.length >= 2) {
        flush()
        const b = new MdBlock()
        b.kind = MdKind.Math
        b.text = rest.substring(0, rest.length - 2).trim()
        out.push(b)
        i++
        continue
      }
      let j = i + 1
      const body: string[] = rest.length > 0 ? [rest] : []
      while (j < lines.length && !lines[j].trim().endsWith(close)) {
        body.push(lines[j])
        j++
      }
      if (j < lines.length) {
        flush()
        const last = lines[j].trim()
        const tail = last.substring(0, last.length - 2)
        if (tail.length > 0) {
          body.push(tail)
        }
        const b = new MdBlock()
        b.kind = MdKind.Math
        b.text = body.join('\n').trim()
        out.push(b)
        i = j + 1
        continue
      }
    }
    if (trimmed.length === 0) {
      flush()
      i++
      continue
    }
    const hm = HEADING.exec(line)
    if (hm !== null) {
      flush()
      const b = new MdBlock()
      b.kind = MdKind.Heading
      b.level = hm[1].length
      b.text = hm[2]
      out.push(b)
      i++
      continue
    }
    if (para.length > 0 && i + 0 < lines.length && new RegExp('^\\s{0,3}(=+|-+)\\s*$').test(line) && !RULE.test(line) ||
      para.length > 0 && new RegExp('^\\s{0,3}=+\\s*$').test(line)) {
      const b = new MdBlock()
      b.kind = MdKind.Heading
      b.level = line.trim().startsWith('=') ? 1 : 2
      b.text = para.join(' ')
      para = []
      out.push(b)
      i++
      continue
    }
    if (RULE.test(line)) {
      flush()
      const b = new MdBlock()
      b.kind = MdKind.Rule
      out.push(b)
      i++
      continue
    }
    if (trimmed.startsWith('>')) {
      flush()
      const body: string[] = []
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        body.push(lines[i].trim().replace(new RegExp('^>\\s?'), ''))
        i++
      }
      const b = new MdBlock()
      b.kind = MdKind.Quote
      b.text = body.join('\n')
      out.push(b)
      continue
    }
    if (trimmed.includes('|') && i + 1 < lines.length && TABLE_SEP.test(lines[i + 1])) {
      flush()
      const b = new MdBlock()
      b.kind = MdKind.Table
      b.rows.push(splitRow(line))
      b.align = splitRow(lines[i + 1]).map((c: string) =>
        c.startsWith(':') && c.endsWith(':') ? 'center' : c.endsWith(':') ? 'end' : 'start')
      i += 2
      while (i < lines.length && lines[i].includes('|') && lines[i].trim().length > 0) {
        b.rows.push(splitRow(lines[i]))
        i++
      }
      out.push(b)
      continue
    }
    const lm = LIST.exec(line)
    if (lm !== null) {
      flush()
      const b = new MdBlock()
      b.kind = MdKind.List
      while (i < lines.length) {
        const m = LIST.exec(lines[i])
        if (m === null) {
          // Continuation lines indented under an item.
          if (lines[i].trim().length > 0 && new RegExp('^\\s{2,}').test(lines[i]) && b.items.length > 0) {
            b.items[b.items.length - 1].text += '\n' + lines[i].trim()
            i++
            continue
          }
          break
        }
        const it = new MdListItem()
        it.level = Math.min(4, Math.floor(m[1].replace(new RegExp('\\t', 'g'), '    ').length / 2))
        it.ordered = new RegExp('^\\d').test(m[2])
        it.index = it.ordered ? parseInt(m[2]) : 0
        let t = m[3]
        const tm = TASK.exec(t)
        if (tm !== null) {
          it.task = tm[1] === ' ' ? 0 : 1
          t = tm[2]
        }
        it.text = t
        b.items.push(it)
        i++
      }
      out.push(b)
      continue
    }
    para.push(line)
    i++
  }
  flush()
  out.forEach((b: MdBlock, n: number) => {
    b.key = `${n}-${b.kind}-${b.text.length}-${b.items.length}-${b.rows.length}`
  })
  return out
}

function looksLikeTex(s: string): boolean {
  return new RegExp('\\\\[a-zA-Z]+|[\\^_{}]|=').test(s) && !new RegExp('^\\d+([.,]\\d+)?$').test(s.trim())
}

/** Inline parser: code, math, links, file refs, bold/italic/strike. */
export function parseInline(src: string): MdSpan[] {
  const out: MdSpan[] = []
  let buf = ''
  const push = (kind: SpanKind, text: string, href: string = '') => {
    if (buf.length > 0) {
      const t = new MdSpan()
      t.text = buf
      out.push(t)
      buf = ''
    }
    const s = new MdSpan()
    s.kind = kind
    s.text = text
    s.href = href
    out.push(s)
  }
  let i = 0
  const n = src.length
  while (i < n) {
    const c = src[i]
    if (c === '\\' && i + 1 < n) {
      const nx = src[i + 1]
      if (nx === '(') {
        const end = src.indexOf('\\)', i + 2)
        if (end > 0) {
          push(SpanKind.Math, src.substring(i + 2, end))
          i = end + 2
          continue
        }
      }
      if ('\\`*_{}[]()#+-.!|~$<>'.includes(nx)) {
        buf += nx
        i += 2
        continue
      }
    }
    if (c === '`') {
      let run = 0
      while (i + run < n && src[i + run] === '`') {
        run++
      }
      const tick = '`'.repeat(run)
      const end = src.indexOf(tick, i + run)
      if (end > 0) {
        const code = src.substring(i + run, end).trim()
        if (isFilePathText(code)) {
          push(SpanKind.CodeFile, code, code)
        } else {
          push(SpanKind.Code, code)
        }
        i = end + run
        continue
      }
      buf += tick
      i += run
      continue
    }
    if (c === '$' && src[i + 1] !== '$') {
      const end = src.indexOf('$', i + 1)
      if (end > i + 1) {
        const inner = src.substring(i + 1, end)
        if (!inner.startsWith(' ') && !inner.endsWith(' ') && looksLikeTex(inner)) {
          push(SpanKind.Math, inner)
          i = end + 1
          continue
        }
      }
    }
    if (c === '$' && src[i + 1] === '$') {
      const end = src.indexOf('$$', i + 2)
      if (end > 0) {
        push(SpanKind.Math, src.substring(i + 2, end))
        i = end + 2
        continue
      }
    }
    if (c === '[' || (c === '!' && src[i + 1] === '[')) {
      const start = c === '!' ? i + 1 : i
      const close = findClose(src, start)
      if (close > 0 && src[close + 1] === '(') {
        const dest = readDestination(src, close + 2)
        const pe = dest.end
        if (pe > 0) {
          const label = src.substring(start + 1, close)
          const href = dest.href
          const kind = href.startsWith('codeg://') ? SpanKind.Ref : isFileHref(href) ? SpanKind.File : SpanKind.Link
          push(kind, label.length > 0 ? label : href, href)
          i = pe + 1
          continue
        }
      }
    }
    if (c === '<') {
      const m = new RegExp('^<(https?://[^>\\s]+)>').exec(src.substring(i))
      if (m !== null) {
        push(SpanKind.Link, m[1], m[1])
        i += m[0].length
        continue
      }
    }
    if (c === 'h' && (i === 0 || new RegExp('[\\s(]').test(src[i - 1]))) {
      const m = new RegExp('^https?://[^\\s<>()\\[\\]]+[^\\s<>()\\[\\].,;:!?\'"]').exec(src.substring(i))
      if (m !== null) {
        push(SpanKind.Link, m[0], m[0])
        i += m[0].length
        continue
      }
    }
    if ((c === '*' || c === '_') ) {
      let run = 0
      while (i + run < n && src[i + run] === c && run < 3) {
        run++
      }
      const marker = c.repeat(run)
      const end = src.indexOf(marker, i + run)
      const leftOk = c === '*' || i === 0 || !new RegExp('\\w').test(src[i - 1])
      if (end > i + run && leftOk && src[i + run] !== ' ') {
        const inner = src.substring(i + run, end)
        push(run === 3 ? SpanKind.BoldItalic : run === 2 ? SpanKind.Bold : SpanKind.Italic, inner)
        i = end + run
        continue
      }
      buf += marker
      i += run
      continue
    }
    if (c === '~' && src[i + 1] === '~') {
      const end = src.indexOf('~~', i + 2)
      if (end > 0) {
        push(SpanKind.Strike, src.substring(i + 2, end))
        i = end + 2
        continue
      }
    }
    buf += c
    i++
  }
  if (buf.length > 0) {
    const t = new MdSpan()
    t.text = buf
    out.push(t)
  }
  return out
}

class LinkDestination {
  href: string = ''
  /** Index of the closing `)`, or -1 when the link is not closed. */
  end: number = -1
}

/**
 * Reads a link destination starting right after `(`. Handles `<path with
 * spaces>`, parentheses inside the path (`a(1).png`) and an optional title.
 */
function readDestination(src: string, from: number): LinkDestination {
  const d = new LinkDestination()
  if (src[from] === '<') {
    const gt = src.indexOf('>', from)
    const inner = gt > 0 ? src.substring(from + 1, gt) : ''
    if (gt > 0 && !inner.includes('\n') && !inner.includes('<')) {
      d.end = src.indexOf(')', gt)
      d.href = inner
      return d
    }
  }
  let depth = 0
  for (let i = from; i < src.length; i++) {
    const c = src[i]
    if (c === '\n') {
      break
    }
    if (c === '(') {
      depth++
    } else if (c === ')') {
      if (depth === 0) {
        d.end = i
        break
      }
      depth--
    }
  }
  if (d.end < 0) {
    d.end = src.indexOf(')', from)
  }
  if (d.end > 0) {
    d.href = src.substring(from, d.end).trim().split(' ')[0]
  }
  return d
}

function findClose(s: string, open: number): number {
  let depth = 0
  for (let i = open; i < s.length; i++) {
    if (s[i] === '[') {
      depth++
    } else if (s[i] === ']') {
      depth--
      if (depth === 0) {
        return i
      }
    }
  }
  return -1
}

/** Symbol for a file name, path or reference (`a/b.go:24`). */
export function fileIconFor(name: string): string {
  const ext = parseFileTarget(name).path.toLowerCase().split('.').pop() ?? ''
  if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'heic', 'bmp'].includes(ext)) {
    return 'picture'
  }
  if (['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'].includes(ext)) {
    return 'play_circle'
  }
  if (ext === 'pdf') {
    return 'doc_text'
  }
  if (['md', 'txt', 'rst'].includes(ext)) {
    return 'doc_plaintext'
  }
  return 'doc'
}
