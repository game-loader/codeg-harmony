// Recognising and resolving the files an agent points at in a reply: Markdown
// links (`[report](/abs/report.md:12)`) and paths written as inline code
// (`src/main.rs:51`, `~/out/demo.mp4`). No UI or network here.

/** A referenced file: its path as written (decoded, `/`-separated) and a line, 0 when none. */
export class FileTarget {
  path: string = ''
  line: number = 0
}

/** Where a referenced file is on the server, in the form the file commands take. */
export class ResolvedFile {
  abs: string = ''
  /** Folder the server reads relative to: the session folder when the file is inside it, else the file's own folder. */
  root: string = ''
  rel: string = ''
  name: string = ''
  line: number = 0
}

// Hosts written without a scheme (`example.com/a`) look like relative paths;
// these suffixes are rarely file extensions. Same list as the web client.
const WEB_SUFFIXES: string[] = ['com', 'net', 'org', 'io', 'dev', 'ai', 'app', 'co', 'cn', 'me', 'xyz', 'info',
  'edu', 'gov', 'uk', 'de', 'jp', 'kr', 'tw', 'hk']

function isWebHost(segment: string): boolean {
  const host = segment.toLowerCase()
  if (host === 'localhost' || host.startsWith('www.')) {
    return true
  }
  if (new RegExp('^\\d{1,3}(\\.\\d{1,3}){3}$').test(host)) {
    return true
  }
  const m = new RegExp('^[^.].*\\.([a-z\\d]+)$').exec(host)
  return m !== null && WEB_SUFFIXES.includes(m[1])
}

/** `main.rs`, `.gitignore`: a name ending in an extension that has a letter in it (so not `v1.2`). */
function hasExtension(name: string): boolean {
  return new RegExp('\\.[A-Za-z\\d]*[A-Za-z][A-Za-z\\d]*$').test(name)
}

/** Whether a name without a directory reads as a file: `index.html`, `.env`, `Makefile`, `README`. */
function isFileName(name: string): boolean {
  if (name.length === 0 || isWebHost(name)) {
    return false
  }
  return hasExtension(name) || new RegExp('^[A-Za-z]+file$', 'i').test(name) ||
  new RegExp('^[A-Z][A-Z\\d]{3,}([-_][A-Z\\d]+)*$').test(name)
}

function isWindowsDrive(p: string): boolean {
  return new RegExp('^[A-Za-z]:[\\\\/]').test(p)
}

function lineFromHash(hash: string): number {
  const m = new RegExp('^(?:L|line=)?(\\d+)(?:-L?\\d+)?$', 'i').exec(hash)
  return m !== null ? Number(m[1]) : 0
}

/**
 * Splits a reference into its path and line. Accepts `file://` URIs, paths
 * with percent-escapes (Markdown destinations), `path:12`, `path:12:3` and
 * `path#L12`.
 */
export function parseFileTarget(ref: string): FileTarget {
  const t = new FileTarget()
  let p = ref.trim()
  if (new RegExp('^file://', 'i').test(p)) {
    p = p.substring(7)
  }
  const hash = p.lastIndexOf('#')
  if (hash > 0) {
    const line = lineFromHash(p.substring(hash + 1))
    if (line > 0) {
      t.line = line
      p = p.substring(0, hash)
    }
  }
  if (p.includes('%')) {
    try {
      p = decodeURIComponent(p)
    } catch (e) {
      // A literal percent sign; keep the text as written.
    }
  }
  p = p.replace(new RegExp('\\\\', 'g'), '/').replace(new RegExp('^/([A-Za-z]:/)'), '$1')
  const pos = new RegExp('^(.+?):(\\d+)(?::\\d+)?$').exec(p)
  if (pos !== null && !pos[1].endsWith('/')) {
    if (t.line === 0) {
      t.line = Number(pos[2])
    }
    p = pos[1]
  }
  t.path = p
  return t
}

/**
 * Whether a Markdown link destination is a local file rather than a web
 * address: `file://…`, `/abs`, `~/x`, `./x`, `../x`, `C:\x`, or a relative
 * path such as `docs/a.md` or `a.ts:12` (same rules as the web client).
 */
export function isFileHref(href: string): boolean {
  const h = href.trim()
  if (h.length === 0 || h.startsWith('#') || h.startsWith('?')) {
    return false
  }
  if (new RegExp('^file://', 'i').test(h)) {
    return true
  }
  if (h.startsWith('//')) {
    return false
  }
  if (h.startsWith('/') || h.startsWith('~/') || h.startsWith('./') || h.startsWith('../') || isWindowsDrive(h)) {
    return true
  }
  const path = parseFileTarget(h).path
  if (new RegExp('^[A-Za-z][A-Za-z\\d+.-]*:').test(path)) {
    return false
  }
  const slash = path.indexOf('/')
  if (slash < 0) {
    return isFileName(path)
  }
  return slash > 0 && !isWebHost(path.substring(0, slash))
}

/**
 * Whether inline code is a path to a file, so it can be opened: it must have a
 * directory and a file extension (`src/a.ts:12`, `~/out/demo.mp4`,
 * `/tmp/build.log`). Branch names, repo slugs, URLs, globs and expressions are
 * left as plain code.
 */
export function isFilePathText(text: string): boolean {
  const s = text.trim()
  if (s.length < 3 || s.length > 300) {
    return false
  }
  if (new RegExp('[\\s<>|*?"\'=(){}\\[\\]$,;!&^`]').test(s) || s.includes('://') || s.startsWith('//') ||
  s.startsWith('-') || s.startsWith('@')) {
    return false
  }
  const p = parseFileTarget(s).path
  const slash = p.indexOf('/')
  if (slash < 0 || !hasExtension(p.substring(p.lastIndexOf('/') + 1))) {
    return false
  }
  // `git@host:owner/repo.git`, `host:8080/a.js`: a colon past a drive letter is not a path.
  if (p.substring(isWindowsDrive(p) ? 2 : 0).includes(':')) {
    return false
  }
  if (p.startsWith('/') || p.startsWith('~/') || p.startsWith('./') || p.startsWith('../') || isWindowsDrive(p)) {
    return true
  }
  return slash > 0 && !isWebHost(p.substring(0, slash))
}

/**
 * A `file://` address for a file in the app's own storage, for the web view.
 * Each segment is escaped, so spaces, `#`, `?`, `%` and non-ASCII names work.
 */
export function localFileUrl(path: string): string {
  return 'file://' + path.split('/').map((seg: string) => encodeURIComponent(seg)).join('/')
}

/** Collapses `.`, `..` and repeated separators in an absolute path. */
function normalize(abs: string): string {
  const drive = isWindowsDrive(abs) ? abs.substring(0, 2) : ''
  const out: string[] = []
  for (const seg of abs.substring(drive.length).split('/')) {
    if (seg === '' || seg === '.') {
      continue
    }
    if (seg === '..') {
      out.pop()
    } else {
      out.push(seg)
    }
  }
  return `${drive}/${out.join('/')}`
}

/**
 * Locates a referenced file on the server. A relative path is taken from the
 * session's folder and `~/` from the server user's home; returns null when the
 * one it needs is unknown (pass '' for either).
 */
export function resolveFile(target: FileTarget, sessionRoot: string, home: string): ResolvedFile | null {
  const p = target.path
  let abs = ''
  if (p.startsWith('~/')) {
    if (home.length === 0) {
      return null
    }
    abs = `${home}/${p.substring(2)}`
  } else if (p.startsWith('/') || isWindowsDrive(p)) {
    abs = p
  } else {
    if (sessionRoot.length === 0) {
      return null
    }
    abs = `${sessionRoot}/${p}`
  }
  const r = new ResolvedFile()
  r.abs = normalize(abs)
  r.line = target.line
  const cut = r.abs.lastIndexOf('/')
  r.name = r.abs.substring(cut + 1)
  if (r.name.length === 0) {
    return null
  }
  const root = sessionRoot.length > 0 ? normalize(sessionRoot) : ''
  if (root.length > 1 && r.abs.startsWith(`${root}/`)) {
    r.root = root
    r.rel = r.abs.substring(root.length + 1)
  } else {
    r.root = cut <= 0 ? '/' : r.abs.substring(0, cut)
    r.rel = r.name
  }
  return r
}
