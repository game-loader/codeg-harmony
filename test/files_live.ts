// The app's file code against a real codeg-server: text, image, video stream,
// streamed download and the browser ticket. Creates its own files in a temp
// folder, so it must run on the machine the server runs on. Read-only for the server.
import { execFileSync } from 'node:child_process'
import { createHash, randomBytes } from 'node:crypto'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'
import { Api } from '@app/net/Api'
import { CodegClient } from '@app/net/CodegClient'
import { ApiError, errorText } from '@app/net/ApiError'
import { downloadWorkspaceFile } from '@app/net/Downloads'
import { ResolvedFile, parseFileTarget, resolveFile } from '@app/session/FileRefs'

const base = `http://${process.env.CODEG_HOST}:${process.env.CODEG_PORT}`
const api = new Api(new CodegClient(base, process.env.CODEG_TOKEN ?? ''))
let fail = 0
function check(name: string, ok: boolean, detail: string = ''): void {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`)
  if (!ok) fail++
}
const sha = (b: Uint8Array) => createHash('sha256').update(b).digest('hex')
const work = mkdtempSync(join(tmpdir(), 'codeg-harmony-files-'))
const proj = join(work, 'proj')
const out = join(work, 'out put')
mkdirSync(join(proj, 'docs', '设计 稿'), { recursive: true })
mkdirSync(out)
mkdirSync(join(work, 'cache'))
const notes = '# 方案\n\nline two with `code` and ünïcödé\n'
writeFileSync(join(proj, 'docs', '设计 稿', '方案 v2.md'), notes)
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64')
writeFileSync(join(proj, 'shot.png'), png)
const big = randomBytes(6 * 1024 * 1024 + 77)
writeFileSync(join(out, 'build(1).zip'), big)
let haveVideo = false
try {
  execFileSync('ffmpeg', ['-v', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=2:size=320x240:rate=15', '-pix_fmt', 'yuv420p', join(out, 'demo.mp4')])
  haveVideo = true
} catch (e) {
  console.log('SKIP  video: ffmpeg is not installed')
}
/** Resolve a reference the way the app does when it is tapped in a session whose folder is `proj`. */
function tap(ref: string, home: string = ''): ResolvedFile {
  const r = resolveFile(parseFileTarget(ref), proj, home)
  if (r === null) throw new Error(`unresolved: ${ref}`)
  return r
}
async function fails(p: Promise<unknown>): Promise<ApiError | null> {
  try { await p; return null } catch (e) { return e instanceof ApiError ? e : new ApiError(-1, 'other', String(e)) }
}

try {
  const home = await api.homeDirectory()
  check('server home directory (what ~/ means)', home === homedir(), home.replace(/\/home\/\w+/, '/home/U'))

  // Text, referenced relative to the session folder, with a line, spaces and CJK in the path.
  let f = tap('docs/设计 稿/方案 v2.md:3')
  check('text: relative reference with :line reads the file', await api.readFile(f.root, f.rel) === notes && f.line === 3, f.rel)
  f = tap(`file://${encodeURI(join(proj, 'docs', '设计 稿', '方案 v2.md'))}`)
  check('text: file:// URI with escapes reads the same file', await api.readFile(f.root, f.rel) === notes)

  // Image.
  f = tap('./shot.png')
  const b64 = await api.readFileBase64(f.root, f.rel, 15000000)
  check('image: bytes identical', sha(Buffer.from(b64, 'base64')) === sha(png), `${Buffer.from(b64, 'base64').length} bytes`)

  // A file outside the session folder (an absolute path, as agents write for build outputs).
  f = tap(join(out, 'build(1).zip'))
  check('outside the session folder: read from its own folder', f.root === out && f.rel === 'build(1).zip')
  const dest = join(work, 'cache', f.name)
  let last = [0, 0]
  let updates = 0
  const n = await downloadWorkspaceFile(api.c, f.root, f.rel, dest, (got: number, of: number) => { last = [got, of]; updates++ })
  check('download: 6 MB archive arrives byte-identical', n === big.length && sha(readFileSync(dest)) === sha(big), `${n} bytes, ${updates} progress updates`)
  check('download: progress ends at the announced size', last[0] === big.length && last[1] === big.length)

  // The browser route: a ticket address that needs no token.
  const url = await api.browserDownloadUrl(f.root, f.rel)
  const viaBrowser = await fetch(url)
  const body = new Uint8Array(await viaBrowser.arrayBuffer())
  check('browser download: ticket address serves the file without a token', viaBrowser.status === 200 && sha(body) === sha(big), `${viaBrowser.headers.get('content-disposition')}`)

  // Text preview refuses a binary: the app then offers saving instead.
  const bin = await fails(api.readFile(f.root, f.rel))
  check('binary file: text preview is refused with a reason (app offers Save)', bin !== null && !bin.isNotFound && errorText(bin).length > 0, bin === null ? 'no error' : errorText(bin))

  if (haveVideo) {
    f = tap(join(out, 'demo.mp4'))
    const token = await api.startVideoPreview(f.root, f.rel)
    const src = readFileSync(join(out, 'demo.mp4'))
    const part = await fetch(api.c.videoUrl(token), { headers: { 'Range': 'bytes=100-1099' } })
    const got = new Uint8Array(await part.arrayBuffer())
    check('video: the player address streams ranges without a token', part.status === 206 && part.headers.get('content-type') === 'video/mp4' && sha(got) === sha(src.subarray(100, 1100)), `${part.status} ${part.headers.get('content-range')}`)
    const whole = await fetch(api.c.videoUrl(token))
    check('video: full stream is byte-identical', whole.status === 200 && sha(new Uint8Array(await whole.arrayBuffer())) === sha(src), `${src.length} bytes`)
    await api.stopVideoPreview(token)
    check('video: the address stops working once the preview is closed', (await fetch(api.c.videoUrl(token))).status === 404)
  }

  // What the app shows for references that do not lead to a file.
  f = tap('docs/missing.md')
  const gone = await fails(api.readFile(f.root, f.rel))
  check('missing file: reported as not found', gone !== null && gone.isNotFound, gone === null ? 'no error' : `${gone.status} ${errorText(gone)}`)
  f = tap(join(proj, 'docs'))
  const dir = await fails(api.readFile(f.root, f.rel))
  check('folder: reported as "Path is not a file"', dir !== null && errorText(dir) === 'Path is not a file', dir === null ? 'no error' : errorText(dir))
  const nodl = await fails(downloadWorkspaceFile(api.c, proj, 'docs/missing.md', join(work, 'cache', 'x'), () => {}))
  check('download of a missing file: server reason, nothing written', nodl !== null && nodl.isNotFound && !existsSync(join(work, 'cache', 'x')), nodl === null ? 'no error' : errorText(nodl))
} catch (e) {
  fail++
  console.log('FAIL  uncaught:', (e as Error).stack)
}
rmSync(work, { recursive: true, force: true })
console.log(fail === 0 ? 'ALL PASS' : `${fail} FAILED`)
process.exit(fail === 0 ? 0 : 1)
