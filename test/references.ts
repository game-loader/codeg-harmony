// Composer references (`@` panel) and the streamed JSON client, run from the app's .ets sources.
import { createServer } from 'node:http'
import {
  RefItem, RefKind, buildFileUri, escapeMarkdownText, expandRefs, mentionAt, plainTitle, refSegments
} from '@app/session/References'
import { CodegClient } from '@app/net/CodegClient'

let fail = 0
function eq(name: string, got: unknown, want: unknown): void {
  const ok = JSON.stringify(got) === JSON.stringify(want)
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : `\n      got  ${JSON.stringify(got)}\n      want ${JSON.stringify(want)}`}`)
  if (!ok) fail++
}
function ref(kind: RefKind, label: string, uri: string): RefItem {
  const r = new RefItem(); r.kind = kind; r.label = label; r.uri = uri; return r
}

// Wire format matches the web's referenceToMarkdown.
const s = ref(RefKind.Session, 'Fix [auth] flow', 'codeg://session/214')
const a = ref(RefKind.Agent, 'Codex', 'codeg://agent/codex')
eq('session markdown escapes the label', s.markdown, '[Fix \\[auth\\] flow](codeg://session/214)')
eq('agent markdown keeps the @', a.markdown, '[@Codex](codeg://agent/codex)')
eq('expand in text order', expandRefs('继续 @Fix [auth] flow 然后 @Codex 帮忙', [a, s]),
  '继续 [Fix \\[auth\\] flow](codeg://session/214) 然后 [@Codex](codeg://agent/codex) 帮忙')
eq('edited-away token stays plain', expandRefs('@Fix [auth', [s]), '@Fix [auth')
eq('two refs with the same token', expandRefs('@A and @A', [ref(RefKind.Session, 'A', 'codeg://session/1'),
  ref(RefKind.Session, 'A', 'codeg://session/2')]), '[A](codeg://session/1) and [A](codeg://session/2)')
eq('escape set', escapeMarkdownText('a*b_c`d<e>'), 'a\\*b\\_c\\`d\\<e\\>')
eq('file uri', buildFileUri('/home/me/my file#1.md'), 'file:///home/me/my%20file%231.md')
eq('title strips links', plainTitle('Re [x](codeg://session/3) done'), 'Re x done')

// `@` opens at start, after whitespace or CJK; never inside words/e-mails.
eq('@ after space', mentionAt('hi @ses', 7), { start: 3, query: 'ses' })
eq('@ in e-mail', mentionAt('mail a@b', 8).start, -1)
eq('@ after CJK', mentionAt('中文@会话', 5), { start: 2, query: '会话' })
eq('bare @', mentionAt('@', 1), { start: 0, query: '' })
eq('space closes the query', mentionAt('x @a b', 6).start, -1)

// Transcript badges.
eq('segments', refSegments('Continue [Fix \\[auth\\] flow](codeg://session/214) and [README](file:///r/README.md)')
  .map((x: any) => [x.text, x.href]),
  [['Continue ', ''], ['Fix [auth] flow', 'codeg://session/214'], [' and [README](file:///r/README.md)', '']])

// Streamed JSON client: a 12 MB body (above the 5 MB buffered cap) and a UTF-8 split across chunks.
const big = JSON.stringify({ turns: Array.from({ length: 60000 }, (_: unknown, i: number) => ({ i, t: '会话内容 '.repeat(20) })) })
const srv = createServer((req, res) => {
  let body = ''
  req.on('data', (c) => { body += c })
  req.on('end', () => {
    if (req.url === '/api/err') { res.writeHead(409, { 'Content-Type': 'application/json' }); res.end('{"code":"turn_in_progress","message":"busy"}'); return }
    res.writeHead(200, { 'Content-Type': 'application/json' })
    const buf = Buffer.from(big)
    let off = 0
    const step = () => { if (off >= buf.length) { res.end(); return } res.write(buf.subarray(off, off + 65537)); off += 65537; setImmediate(step) }
    step()
  })
})
await new Promise<void>((r) => srv.listen(0, '127.0.0.1', () => r()))
const port = (srv.address() as any).port
const c = new CodegClient(`http://127.0.0.1:${port}`, 't')
const got: any = await c.call('big')
eq('streamed body size', Buffer.byteLength(big) > 12e6, true)
eq('streamed body parses', [got.turns.length, got.turns[59999].t.length], [60000, 100])
try { await c.call('err'); eq('error status', 'no throw', 'throw') } catch (e: any) { eq('error status', [e.status, e.code], [409, 'turn_in_progress']) }
srv.close()

if (fail > 0) { console.log(`${fail} failed`); process.exit(1) }
console.log('references: all passed')
