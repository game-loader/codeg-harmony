// The app's real SessionController against the local stand-in server:
// an existing conversation whose agent is not running (resume), refusals, reclaim, races.
import { Api } from '@app/net/Api'
import { CodegClient } from '@app/net/CodegClient'
import { AppPrefs } from '@app/store/ServerStore'
import { Draft, SessionController } from '@app/session/SessionController'
import { SelectorPrefs } from '@app/session/AgentOptionsModel'
import { AgentOptions, ConfigOption, MODE_KEY } from '@app/session/Interactive'
import { FolderDetail } from '@app/model/Models'

let fail = 0
function check(name: string, ok: boolean, detail: string = ''): void {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`)
  if (!ok) fail++
}
const st = (o: AgentOptions | null): string => o === null ? 'null' : o.rows.map((r: ConfigOption) => `${r.id}=${r.current}`).join(' ')
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms))
const fake = './fake_server.mjs'
const { startFake } = await import(fake)
const f = await startFake()
const api = new Api(new CodegClient(f.url, 'test-token'))
AppPrefs.init({} as any)
const folder = new FolderDetail(); folder.id = 1; folder.path = '/work/repo'
const srv = (cid: string): string => f.conns.get(cid).config.map((o: any) => `${o.id}=${o.kind.current_value}`).join(' ')

try {
  // This device last used haiku; the conversation itself last ran with sonnet + plan (set on another device).
  SelectorPrefs.remember('claude_code', 'model', 'haiku')
  f.stored.set('sess-1', { mode_id: 'plan', config_values: { mode: 'plan', model: 'sonnet', effort: 'medium' } })

  const c = new SessionController(api)
  await c.open(7, folder)
  check('existing conversation: opening it starts no agent', f.count('acp_connect') === 0 && c.connectionId === null && c.opts.options === null)

  // Open the options sheet; tap twice and send-path resolve at the same moment.
  const phases: string[] = []
  const watch = setInterval(() => { if (phases[phases.length - 1] !== c.opts.phase) phases.push(c.opts.phase) }, 20)
  await Promise.all([c.loadOptions(), c.loadOptions(), (c as any).resolveConnection()])
  clearInterval(watch)
  check('opening options: one agent start, shared by concurrent callers', f.count('acp_connect') === 1, `acp_connect calls: ${f.count('acp_connect')}`)
  const req = f.last('acp_connect')
  check('opening options: the session is resumed, with this device\'s picks as fallback', req.sessionId === 'sess-1' && req.preferredConfigValues?.model === 'haiku', JSON.stringify(req))
  check('opening options: shows a spinner until the agent reports', phases.includes('connecting') && c.opts.phase === 'ready', `phases: ${phases.join(' -> ')}`)
  check('opening options: shows the session\'s own settings, not this device\'s', st(c.opts.options) === 'mode=plan model=sonnet effort=medium', st(c.opts.options))
  check('opening options: slash commands come from the live session', c.opts.options!.commands.join() === 'review')
  const cid = c.connectionId as string

  await c.pickOption('model', 'opus')
  check('pick: applied on the server and shown', srv(cid) === 'mode=plan model=opus effort=medium' && st(c.opts.options) === srv(cid) && c.opts.error === '', srv(cid))
  check('pick: remembered for new sessions on this device', SelectorPrefs.load('claude_code').model === 'opus')
  check('pick: stored for the session on the server', f.stored.get('sess-1').config_values.model === 'opus')

  await c.pickOption('model', 'locked')
  check('agent refuses a value: selection returns to what the agent runs', st(c.opts.options) === srv(cid) && c.opts.options!.valueOf('model') === 'opus', st(c.opts.options))
  check('agent refuses a value: the reason is shown in the sheet', c.opts.error.includes('LOCKED') && c.opts.phase === 'ready' && c.error === '', c.opts.error)
  check('agent refuses a value: not remembered', SelectorPrefs.load('claude_code').model === 'opus')

  f.pushFromElsewhere(cid, 'effort', 'high')
  await sleep(100)
  check('change made on another device: shown here', c.opts.options!.valueOf('effort') === 'high', st(c.opts.options))
  const revBefore = c.opts.rev
  f.pushFromElsewhere(cid, 'mode', 'default')
  await sleep(100)
  check('mode change from another device: shown, rows redrawn', c.opts.options!.valueOf('mode') === 'default' && c.opts.rev > revBefore, `label "${c.opts.options!.summary}"`)

  // The server stops idle agents after 3 minutes.
  f.reclaim(cid)
  await sleep(100)
  check('agent reclaimed: last known settings stay on screen', c.connectionId === null && st(c.opts.options) === 'mode=default model=opus effort=high')
  await c.pickOption('effort', 'low')
  const cid2 = c.connectionId as string
  check('agent reclaimed: the next pick restarts it and applies', cid2 !== null && cid2 !== cid && f.count('acp_connect') === 2 && srv(cid2) === 'mode=default model=opus effort=low' && c.opts.error === '', cid2 === null ? 'no connection' : srv(cid2))
  check('agent reclaimed: restarted by resuming the same session', f.last('acp_connect').sessionId === 'sess-1')

  // A connection id the server no longer knows, without a detach notice (socket was down).
  f.conns.delete(cid2)
  await c.pickOption('mode', 'plan')
  const cid3 = c.connectionId as string
  check('stale connection id: detected and replaced', cid3 !== cid2 && srv(cid3) === 'mode=plan model=opus effort=low', srv(cid3))

  // The agent cannot start.
  f.reclaim(cid3)
  await sleep(100)
  f.failConnect = 1
  await c.loadOptions()
  check('agent fails to start: the sheet says why', c.opts.phase === 'error' && c.opts.error.includes('boom'), c.opts.error)
  await c.loadOptions(true)
  check('agent fails to start: Try again recovers', c.opts.phase === 'ready' && st(c.opts.options) === 'mode=plan model=opus effort=low', st(c.opts.options))

  // Slow agent: the pick waits for it instead of being dropped.
  f.reclaim(c.connectionId)
  await sleep(100)
  f.readyDelayMs = 2500
  const t0 = Date.now()
  await c.pickOption('model', 'haiku')
  check('slow agent start: the pick waits and still applies', srv(c.connectionId as string).includes('model=haiku') && Date.now() - t0 >= 2500, `${Date.now() - t0} ms`)
  check('nothing left busy', c.opts.applying === '' && !c.opts.locked)
  c.dispose()

  // A new chat with no project folder: picks made before the first message, then the first send.
  f.readyDelayMs = 200
  const chat = new SessionController(api)
  chat.startDraft(null, 'claude_code')
  await chat.loadOptions()
  await chat.pickOption('mode', 'plan')
  await chat.pickOption('effort', 'high')
  const startsBefore = f.count('acp_connect')
  check('new chat: picks before the first message start nothing', f.count('acp_connect') === startsBefore && chat.opts.options!.valueOf('mode') === 'plan')
  const d = new Draft()
  d.text = 'hello'
  const sent = await chat.send(d)
  const first = f.last('acp_connect')
  check('new chat: the first message starts the agent with the picks', sent && f.count('acp_connect') === startsBefore + 1 && first.sessionId === undefined && first.preferredConfigValues.mode === 'plan' && first.preferredConfigValues.effort === 'high', JSON.stringify(first.preferredConfigValues))
  check('new chat: the agent runs in the chat\'s own folder', first.workingDir === '/data/chat-sessions/2026-11-11/abc' && f.last('acp_prompt').folderId === 4 && f.last('acp_prompt').conversationId === 9, first.workingDir)
  check('new chat: the composer shows what the session runs', srv(chat.connectionId as string) === 'mode=plan model=haiku effort=high' && st(chat.opts.options) === srv(chat.connectionId as string), st(chat.opts.options))
  chat.dispose()

  // An agent with modes but no config options: the mode has its own row and its own server command.
  f.modesOnly = true
  const m = new SessionController(api)
  m.startDraft(folder, 'gemini')
  await m.loadOptions()
  check('modes-only agent: the mode row is offered', st(m.opts.options) === `${MODE_KEY}=auto`, st(m.opts.options))
  await m.pickOption(MODE_KEY, 'plan')
  await (m as any).resolveConnection()
  check('modes-only agent: a new session starts in the picked mode', f.last('acp_connect').preferredModeId === 'plan' && f.last('acp_connect').preferredConfigValues === undefined, JSON.stringify(f.last('acp_connect')))
  await m.loadOptions()
  const setsBefore = f.count('acp_set_mode')
  await m.pickOption(MODE_KEY, 'default')
  check('modes-only agent: changing it on a running session uses set_mode', f.count('acp_set_mode') === setsBefore + 1 && f.conns.get(m.connectionId).modes.current_mode_id === 'default' && m.opts.options!.valueOf(MODE_KEY) === 'default' && m.opts.error === '', `label "${m.opts.options!.summary}"`)
  m.dispose()
} catch (e) {
  fail++
  console.log('FAIL  uncaught:', (e as Error).stack)
}
f.stop()
console.log(fail === 0 ? 'ALL PASS' : `${fail} FAILED`)
process.exit(fail === 0 ? 0 : 1)
