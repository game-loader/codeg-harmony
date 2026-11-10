export class DiffLine {
  kind: string = ' ' // '+', '-', ' ', '@'
  text: string = ''
  oldNo: number = 0
  newNo: number = 0
}

export class FileDiff {
  path: string = ''
  lines: DiffLine[] = []
  additions: number = 0
  deletions: number = 0
}

/** Parses git unified diffs, bare unified diffs and minimal ---/+++ forms. */
export function parseUnifiedDiff(text: string): FileDiff[] {
  const out: FileDiff[] = []
  let cur: FileDiff | null = null
  let oldNo = 0
  let newNo = 0
  const ensure = (): FileDiff => {
    if (cur === null) {
      cur = new FileDiff()
      out.push(cur)
    }
    return cur
  }
  for (const raw of text.split('\n')) {
    const line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw
    if (line.startsWith('diff --git ')) {
      cur = new FileDiff()
      const m = new RegExp(' b/(.+)$').exec(line)
      cur.path = m !== null ? m[1] : line.substring(11)
      out.push(cur)
      continue
    }
    if (line.startsWith('+++ ')) {
      const f = ensure()
      const p = line.substring(4).replace(new RegExp('^b/'), '')
      if (p !== '/dev/null') {
        f.path = p
      }
      continue
    }
    if (line.startsWith('--- ')) {
      if (cur === null || (cur as FileDiff).lines.length > 0) {
        cur = new FileDiff()
        out.push(cur)
      }
      const p = line.substring(4).replace(new RegExp('^a/'), '')
      if ((cur as FileDiff).path.length === 0 && p !== '/dev/null') {
        (cur as FileDiff).path = p
      }
      continue
    }
    if (line.startsWith('index ') || line.startsWith('new file') || line.startsWith('deleted file') ||
      line.startsWith('similarity') || line.startsWith('rename ') || line.startsWith('old mode') ||
      line.startsWith('new mode') || line.startsWith('\\ No newline')) {
      continue
    }
    const f = ensure()
    const l = new DiffLine()
    if (line.startsWith('@@')) {
      const m = new RegExp('^@@ -(\\d+)(?:,\\d+)? \\+(\\d+)').exec(line)
      if (m !== null) {
        oldNo = Number(m[1])
        newNo = Number(m[2])
      }
      l.kind = '@'
      l.text = line
    } else if (line.startsWith('+')) {
      l.kind = '+'
      l.text = line.substring(1)
      l.newNo = newNo++
      f.additions++
    } else if (line.startsWith('-')) {
      l.kind = '-'
      l.text = line.substring(1)
      l.oldNo = oldNo++
      f.deletions++
    } else {
      if (f.lines.length === 0 && line.length === 0) {
        continue
      }
      l.kind = ' '
      l.text = line.startsWith(' ') ? line.substring(1) : line
      l.oldNo = oldNo++
      l.newNo = newNo++
    }
    f.lines.push(l)
  }
  return out.filter((d: FileDiff) => d.lines.length > 0)
}

/** Builds a diff from an old/new string pair, the way Edit tool inputs carry them. */
export function diffFromStrings(path: string, oldText: string, newText: string): FileDiff {
  const d = new FileDiff()
  d.path = path
  const a = oldText.length > 0 ? oldText.split('\n') : []
  const b = newText.length > 0 ? newText.split('\n') : []
  // Trim the common prefix and suffix, then show the middle as -/+.
  let p = 0
  while (p < a.length && p < b.length && a[p] === b[p]) {
    p++
  }
  let s = 0
  while (s < a.length - p && s < b.length - p && a[a.length - 1 - s] === b[b.length - 1 - s]) {
    s++
  }
  const ctxStart = Math.max(0, p - 2)
  for (let i = ctxStart; i < p; i++) {
    d.lines.push(mk(' ', a[i], i + 1, i + 1))
  }
  for (let i = p; i < a.length - s; i++) {
    d.lines.push(mk('-', a[i], i + 1, 0))
    d.deletions++
  }
  for (let i = p; i < b.length - s; i++) {
    d.lines.push(mk('+', b[i], 0, i + 1))
    d.additions++
  }
  const tailEnd = Math.min(a.length, a.length - s + 2)
  for (let i = a.length - s; i < tailEnd; i++) {
    d.lines.push(mk(' ', a[i], i + 1, i + 1 + (b.length - a.length)))
  }
  return d
}

function mk(kind: string, text: string, o: number, n: number): DiffLine {
  const l = new DiffLine()
  l.kind = kind
  l.text = text
  l.oldNo = o
  l.newNo = n
  return l
}
