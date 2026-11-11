// Drives the app's real SessionController / AgentOptionsModel against the live server.
// No prompt is ever sent, so no conversation is created and no model tokens are used.
import { Api } from '@app/net/Api'
import { CodegClient } from '@app/net/CodegClient'
import { AppPrefs } from '@app/store/ServerStore'
import { SessionController } from '@app/session/SessionController'
import { SelectorPrefs } from '@app/session/AgentOptionsModel'
import { AgentOptions, ConfigOption, MODE_KEY } from '@app/session/Interactive'
import { FolderDetail } from '@app/model/Models'
import { mkdtempSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const base = `http://${process.env.CODEG_HOST}:${process.env.CODEG_PORT}`
const api = new Api(new CodegClient(base, process.env.CODEG_TOKEN ?? ''))
AppPrefs.init({} as any)
const AGENT = process.argv[2] ?? 'claude_code'
let fail = 0
const opened: string[] = []
function check(name: string, ok: boolean, detail: string = ''): void {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`)
  if (!ok) fail++
}
function state(o: AgentOptions | null): string {
  return o === null ? 'null' : o.rows.map((r: ConfigOption) => `${r.id}=${r.current}`).join(' ')
}
async function serverState(cid: string): Promise<AgentOptions> {
  // Independent read, straight from the server, not through the controller.
  const res = await fetch(`${base}/api/acp_get_session_snapshot`, { method: 'POST',
    headers: { 'Authorization': `Bearer ${process.env.CODEG_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ connectionId: cid }) })
  return AgentOptions.from(await res.json())
}
function other(r: ConfigOption): string {
  return r.choices.find(c => c.value !== r.current)!.value
}
const folder = new FolderDetail()
folder.path = mkdtempSync(join(tmpdir(), 'codeg-harmony-test-'))
folder.name = 'test'

async function main(): Promise<void> {
  // ---- 1. New-session sheet / unsent draft: catalog + saved picks ----
  const draft = new SessionController(api)
  draft.startDraft(folder, AGENT)
  await draft.loadOptions()
  const d0 = draft.opts.options
  check('draft: options load without a connection', draft.opts.phase === 'ready' && d0 !== null && d0.rows.length > 0, state(d0))
  const model0 = d0!.row('model')!
  const mode0 = d0!.primaryRows.find(r => r.id !== 'model')!
  const wantModel = AGENT === 'claude_code' ? 'haiku' : other(model0)
  const wantMode = other(mode0)
  await draft.pickOption(mode0.id, wantMode)
  check('draft: tapping a mode chip selects it', draft.opts.options!.valueOf(mode0.id) === wantMode, `${mode0.id}: ${mode0.current} -> ${draft.opts.options!.valueOf(mode0.id)}`)
  const before = d0!.rows.map(r => `${r.id}:${r.choices.length}`).join(' ')
  await draft.pickOption('model', wantModel)
  const d1 = draft.opts.options!
  check('draft: tapping a model chip selects it', d1.valueOf('model') === wantModel && d1.valueOf(mode0.id) === wantMode, state(d1))
  console.log(`      lists before: ${before}\n      lists for ${wantModel}: ${d1.rows.map(r => `${r.id}:${r.choices.length}`).join(' ')}`)
  const p = SelectorPrefs.load(AGENT)
  check('draft: picks are saved for the next new session', p.model === wantModel && (p.config.get(mode0.id) ?? p.mode) === wantMode, JSON.stringify({ mode: p.mode, config: [...p.config] }))
  check('draft: nothing was started on the server', draft.connectionId === null && draft.conversationId === 0)
  draft.dispose()

  // ---- 2. A fresh draft opens on the saved picks ----
  const ctrl = new SessionController(api)
  ctrl.startDraft(folder, AGENT)
  await ctrl.loadOptions()
  check('new draft: opens on the saved picks', ctrl.opts.options!.valueOf('model') === wantModel && ctrl.opts.options!.valueOf(mode0.id) === wantMode, `button label "${ctrl.opts.options!.summary}"`)

  // ---- 3. What the first send does: start the agent with the saved picks ----
  const t0 = Date.now()
  await (ctrl as any).resolveConnection()
  const cid1 = ctrl.connectionId as string
  opened.push(cid1)
  await ctrl.loadOptions()
  const s1 = await serverState(cid1)
  check('started session: the server applied the picks', s1.valueOf('model') === wantModel && s1.valueOf(mode0.id) === wantMode, `server: ${state(s1)}  (${Date.now() - t0} ms)`)
  check('started session: the sheet shows the session\'s real state', ctrl.opts.phase === 'ready' && state(ctrl.opts.options) === state(s1), state(ctrl.opts.options))
  check('started session: live socket attached', (ctrl as any).attached === true)

  // ---- 4. Change settings on the running session ----
  const liveModel = ctrl.opts.options!.row('model')!
  const nextModel = AGENT === 'claude_code' ? 'sonnet' : other(liveModel)
  await ctrl.pickOption('model', nextModel)
  const s2 = await serverState(cid1)
  check('running session: model change reaches the agent', s2.valueOf('model') === nextModel && ctrl.opts.options!.valueOf('model') === nextModel && ctrl.opts.error === '', `server: ${state(s2)}`)
  const liveMode = ctrl.opts.options!.row(mode0.id)!
  const nextMode = liveMode.choices.find(c => c.value !== liveMode.current && c.value !== wantMode)!.value
  await ctrl.pickOption(mode0.id, nextMode)
  const s3 = await serverState(cid1)
  check('running session: mode change reaches the agent', s3.valueOf(mode0.id) === nextMode && ctrl.opts.options!.valueOf(mode0.id) === nextMode, `server: ${state(s3)}  label "${ctrl.opts.options!.summary}"`)
  const extra = ctrl.opts.options!.moreRows[0]
  if (extra !== undefined) {
    const v = other(extra)
    await ctrl.pickOption(extra.id, v)
    const s4 = await serverState(cid1)
    check(`running session: "${extra.name}" change reaches the agent`, s4.valueOf(extra.id) === v, `${extra.id}=${s4.valueOf(extra.id)}`)
  }
  check('running session: applying flag cleared, nothing stuck', ctrl.opts.applying === '' && !ctrl.opts.locked)

  // ---- 5. A choice the session does not offer is refused, with a reason ----
  const keep = state(ctrl.opts.options)
  await ctrl.pickOption('model', 'no-such-model')
  check('invalid choice: refused, state unchanged, reason shown', state(ctrl.opts.options) === keep && ctrl.opts.error.length > 0 && ctrl.opts.phase === 'ready', ctrl.opts.error)

  ctrl.dispose()
}

main().catch((e: any) => { fail++; console.log('FAIL  uncaught:', e?.message ?? e, e?.stack ?? '') })
  .finally(async () => {
    for (const cid of opened) {
      try { await api.c.send('acp_disconnect', { 'connectionId': cid }) } catch (e) { /* already gone */ }
    }
    console.log(`cleanup: closed ${opened.length} test connection(s)`)
    console.log(fail === 0 ? 'ALL PASS' : `${fail} FAILED`)
    process.exit(fail === 0 ? 0 : 1)
  })
