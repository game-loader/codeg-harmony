// File references in agent replies (recognition, resolution) and the streamed
// download, run from the app's real .ets sources.
import { createHash, randomBytes } from 'node:crypto'
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { isFileHref, isFilePathText, parseFileTarget, resolveFile } from '@app/session/FileRefs'
import { SpanKind, fileIconFor, parseInline } from '@app/components/MarkdownParse'
import { splitUserResources } from '@app/session/Transcript'
import { Api } from '@app/net/Api'
import { CodegClient } from '@app/net/CodegClient'
import { ApiError } from '@app/net/ApiError'
import { copyFileInto, downloadWorkspaceFile, downloadsDir, pruneDownloads } from '@app/net/Downloads'

let fail = 0
function check(name: string, ok: boolean, detail: string = ''): void {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`)
  if (!ok) fail++
}
function eq(name: string, got: unknown, want: unknown): void {
  check(name, JSON.stringify(got) === JSON.stringify(want), JSON.stringify(got) === JSON.stringify(want) ? '' : `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`)
}
const pt = (s: string): [string, number] => { const t = parseFileTarget(s); return [t.path, t.line] }

// ---- parsing a reference (shapes taken from real agent replies) ----
eq('target: absolute path', pt('/home/u/project/RE/数据包_解压/分析报告.md'), ['/home/u/project/RE/数据包_解压/分析报告.md', 0])
eq('target: path:line', pt('/home/u/codeg/src-tauri/src/forge/mod.rs:1'), ['/home/u/codeg/src-tauri/src/forge/mod.rs', 1])
eq('target: path:line:column', pt('backend/internal/store/checkout_preview.go:24:7'), ['backend/internal/store/checkout_preview.go', 24])
eq('target: #L range', pt('src/a.ts#L10-25'), ['src/a.ts', 10])
eq('target: file:// URI with escapes', pt('file:///home/u/My%20Docs/a%20b.md'), ['/home/u/My Docs/a b.md', 0])
eq('target: escaped # and ? stay in the name', pt('file:///tmp/a%23b%3Fc.txt'), ['/tmp/a#b?c.txt', 0])
eq('target: Windows drive URI', pt('file:///C:/Users/a/b.txt'), ['C:/Users/a/b.txt', 0])
eq('target: Windows backslashes', pt('C:\\repo\\src\\a.rs:12'), ['C:/repo/src/a.rs', 12])
eq('target: literal percent sign', pt('/tmp/100%.txt'), ['/tmp/100%.txt', 0])
eq('target: a #fragment that is not a line stays', pt('/tmp/notes.md#intro'), ['/tmp/notes.md#intro', 0])

// ---- Markdown link destinations ----
const fileHrefs = ['/home/u/a.md', '/home/u/project/open-u60-pro', 'file:///tmp/x.png', '~/out/demo.mp4', './a.md', '../site/a.md',
  'docs/round3/results.md', 'a.ts:12', 'index.html', '.gitignore', 'Makefile', 'README', 'C:\\repo\\a.txt', 'deploy.sh']
const notFileHrefs = ['https://example.com/a.md', 'http://localhost:3000/x', 'example.com/docs/a.html', 'www.foo.bar/x', 'github.com/a/b',
  '127.0.0.1/a.txt', 'mailto:a@b.c', 'codeg://session/3', '#section', '//cdn.example.com/x.js', 'foo', 'v1.2.3', '']
eq('link: local files recognised', fileHrefs.filter(h => !isFileHref(h)), [])
eq('link: web addresses and words left alone', notFileHrefs.filter(h => isFileHref(h)), [])

// ---- paths written as inline code ----
const codePaths = ['test/run.sh', 'gateway/test_client.py', 'backend/crates/gateway-admin/src/use_case/auth/service.rs:51',
  '~/tdgram-v0.3.0-with-api-unsigned.hap', '/tmp/rustcc/env.sh', 'src/components/ai-elements/message.tsx', './dist/app.hap',
  '../shared/util.ts', 'C:\\Users\\a\\report.docx', 'entry/src/main/ets/views/FilesView.ets#L40', 'docs/设计/方案.md']
const notCodePaths = ['game-loader/harmony-tdgram', 'google.com/android/uncertified', '/home/u', '~/redroid/data13', './web-transport',
  'main.rs', 'origin/main', 'feat/foo-1.2', 'github.com/a/b.git', 'git@github.com:owner/repo.git', 'node_modules/.bin/esbuild',
  'a/b.c d', '--out=a/b.txt', '$HOME/x.txt', 'http://x/y.png', '//host/x.png', 'src/**/*.ts', '1/2.5', 'application/json',
  'localhost:3080/api/health.json', 'foo(a/b.ts)', 'a/b.ts,c/d.ts', 'npm run build', 'x']
eq('code: file paths recognised', codePaths.filter(p => !isFilePathText(p)), [])
eq('code: branches, slugs, URLs, globs, commands left as code', notCodePaths.filter(p => isFilePathText(p)), [])

// ---- locating the file on the server ----
const rf = (ref: string, root: string, home: string) => { const r = resolveFile(parseFileTarget(ref), root, home); return r === null ? null : [r.abs, r.root, r.rel, r.line] }
eq('resolve: absolute, inside the session folder', rf('/work/repo/src/a.ts:5', '/work/repo', ''), ['/work/repo/src/a.ts', '/work/repo', 'src/a.ts', 5])
eq('resolve: absolute, outside it (read from its own folder)', rf('/home/u/artifacts/demo.mp4', '/work/repo', ''), ['/home/u/artifacts/demo.mp4', '/home/u/artifacts', 'demo.mp4', 0])
eq('resolve: relative, from the session folder', rf('docs/round3/results.md', '/work/repo/', ''), ['/work/repo/docs/round3/results.md', '/work/repo', 'docs/round3/results.md', 0])
eq('resolve: ../ leaves the session folder', rf('../site/a.md', '/work/repo', ''), ['/work/site/a.md', '/work/site', 'a.md', 0])
eq('resolve: a look-alike sibling folder is not inside', rf('/work/repo-old/a.md', '/work/repo', ''), ['/work/repo-old/a.md', '/work/repo-old', 'a.md', 0])
eq('resolve: ~/ uses the server home', rf('~/out/demo.mp4', '/work/repo', '/home/u'), ['/home/u/out/demo.mp4', '/home/u/out', 'demo.mp4', 0])
eq('resolve: ~/ without a known home', rf('~/out/demo.mp4', '/work/repo', ''), null)
eq('resolve: relative without a session folder', rf('src/a.ts', '', ''), null)
eq('resolve: file in the filesystem root', rf('/a.txt', '', ''), ['/a.txt', '/', 'a.txt', 0])
eq('resolve: Windows path', rf('C:\\repo\\src\\a.rs:12', 'C:/repo', ''), ['C:/repo/src/a.rs', 'C:/repo', 'src/a.rs', 12])
eq('resolve: a folder path ending in / has no file', rf('/work/repo/', '', ''), ['/work/repo', '/work', 'repo', 0])

// ---- what the transcript renders ----
const spans = parseInline('See [report](/home/u/out/report.md:3), [docs](docs/a.md), `src/main.rs:51`, `origin/main`, [site](https://x.dev/a.md), [app](www.x.dev) and ![shot](/tmp/s.png).')
eq('transcript: span kinds', spans.filter(s => s.kind !== SpanKind.Text).map(s => [s.kind, s.text, s.href]), [
  [SpanKind.File, 'report', '/home/u/out/report.md:3'], [SpanKind.File, 'docs', 'docs/a.md'], [SpanKind.CodeFile, 'src/main.rs:51', 'src/main.rs:51'],
  [SpanKind.Code, 'origin/main', ''], [SpanKind.Link, 'site', 'https://x.dev/a.md'], [SpanKind.Link, 'app', 'www.x.dev'], [SpanKind.File, 'shot', '/tmp/s.png']])
eq('transcript: bracketed and parenthesised link targets', parseInline('[a](</home/u/white background/fr3 clean.jpg>) and [b](/tmp/shot(1).png "title")').filter(s => s.kind === SpanKind.File).map(s => s.href), ['/home/u/white background/fr3 clean.jpg', '/tmp/shot(1).png'])
eq('transcript: icon follows the file type, ignoring :line', [fileIconFor('/a/demo.mp4'), fileIconFor('shot.PNG'), fileIconFor('src/a.go:24'), fileIconFor('notes.md#L3')], ['play_circle', 'picture', 'doc', 'doc_plaintext'])
const user = splitUserResources('look at [spec.pdf](file:///data/uploads/spec.pdf) and [a b.png](file:///data/uploads/a%20b.png) please')
eq('user message: attachments keep their target', [user.text, user.files.map(f => [f.name, f.href])], ['look at  and  please', [['spec.pdf', 'file:///data/uploads/spec.pdf'], ['a b.png', 'file:///data/uploads/a%20b.png']]])

// ---- streamed download ----
const fake = './fake_server.mjs'
const { startFake } = await import(fake)
const f = await startFake()
const work = mkdtempSync(join(tmpdir(), 'codeg-harmony-files-'))
const sha = (p: string) => createHash('sha256').update(readFileSync(p)).digest('hex')
try {
  const c = new CodegClient(f.url, 'test-token')
  const srcDir = join(work, 'server'); const cache = join(work, 'cache')
  downloadsDir(srcDir)
  const big = join(srcDir, 'demo video.mp4')
  writeFileSync(big, randomBytes(3 * 1024 * 1024 + 4321))
  const dir = downloadsDir(cache)
  check('downloads folder is created', existsSync(dir) && downloadsDir(cache) === dir)

  const dest = join(dir, 'demo video.mp4')
  const ticks: number[][] = []
  const n = await downloadWorkspaceFile(c, srcDir, 'demo video.mp4', dest, (got: number, of: number) => { ticks.push([got, of]) })
  check('download: bytes identical to the server file', n === 3 * 1024 * 1024 + 4321 && sha(dest) === sha(big), `${n} bytes`)
  check('download: request names the folder and relative path', f.last('download_workspace_file').rootPath === srcDir && f.last('download_workspace_file').path === 'demo video.mp4')
  check('download: progress rises to the announced size', ticks.length > 1 && ticks.every((t, i) => i === 0 || t[0] > ticks[i - 1][0]) && ticks[ticks.length - 1][0] === n && ticks[ticks.length - 1][1] === n, `${ticks.length} updates`)

  const gone = join(dir, 'nope.bin')
  let err: unknown = null
  try { await downloadWorkspaceFile(c, srcDir, 'nope.bin', gone, () => {}) } catch (e) { err = e }
  check('download: missing file reports the server\'s reason', err instanceof ApiError && (err as ApiError).isNotFound && (err as ApiError).message === 'File does not exist', String((err as Error)?.message))
  check('download: nothing is left behind after a failure', !existsSync(gone))

  f.dropDownloadAfter = 500000
  const cut = join(dir, 'cut.mp4')
  err = null
  try { await downloadWorkspaceFile(c, srcDir, 'demo video.mp4', cut, () => {}) } catch (e) { err = e }
  check('download: a dropped connection is an error, not a short file', err instanceof ApiError && !existsSync(cut), String((err as Error)?.message))
  f.dropDownloadAfter = 0

  // Saving: the picker hands back a file it created; here one that already holds longer content.
  const picked = join(work, 'picked.mp4')
  writeFileSync(picked, randomBytes(4 * 1024 * 1024))
  await copyFileInto(dest, picked)
  check('save: the chosen file ends up identical (old content replaced)', sha(picked) === sha(big))

  const old = join(dir, 'old.zip'); writeFileSync(old, 'x')
  const twoDaysAgo = Date.now() / 1000 - 2 * 86400
  utimesSync(old, twoDaysAgo, twoDaysAgo)
  pruneDownloads(dir)
  check('cache: downloads older than a day are removed, recent ones kept', !existsSync(old) && existsSync(dest), readdirSync(dir).join(', '))

  const url = await new Api(c).browserDownloadUrl(srcDir, 'demo video.mp4')
  check('browser download: a ticket address on the same server', url === `${f.url}/api/workspace_download/tkt123` && f.last('workspace_download_ticket').kind === 'file', url.replace(f.url, '<server>'))
} catch (e) {
  fail++
  console.log('FAIL  uncaught:', (e as Error).stack)
}
f.stop()
rmSync(work, { recursive: true, force: true })
console.log(fail === 0 ? 'ALL PASS' : `${fail} FAILED`)
process.exit(fail === 0 ? 0 : 1)
