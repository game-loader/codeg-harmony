import { readFileSync } from 'node:fs'
import { AgentOptions, MODE_KEY } from '@app/session/Interactive'

let fail = 0
function check(name: string, ok: boolean, detail: string = ''): void {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`)
  if (!ok) fail++
}
// Catalogs as codeg-server 0.42.2 returned them (acp_describe_agent_options).
for (const agent of ['claude_code', 'codex']) {
  const raw = JSON.parse(readFileSync(`fixtures/options_${agent}.json`, 'utf8'))
  const want: Record<string, number> = {}
  for (const c of raw.config_options) want[c.id] = c.kind.options.length
  const now = AgentOptions.from(raw)
  const got: Record<string, number> = {}
  for (const r of now.rows) got[r.id] = r.choices.length
  console.log(`\n== ${agent}: server sends ${JSON.stringify(want)}`)
  check(`${agent}: every option lists the server's choices`, JSON.stringify(got) === JSON.stringify(want), JSON.stringify(got))
  check(`${agent}: current values match the server`, raw.config_options.every((c: any) => now.valueOf(c.id) === c.kind.current_value))
  check(`${agent}: mode is not listed twice`, !now.showModes && now.row(MODE_KEY) === undefined)
  console.log(`   button label: "${now.summary}"   primary: ${now.primaryRows.map(r => r.id)}   more: ${now.moreRows.map(r => r.id)}`)
}
// Shapes none of the installed agents send, built to the server's Rust types.
const modesOnly = AgentOptions.from({ modes: { current_mode_id: 'b', available_modes: [{ id: 'a', name: 'A' }, { id: 'b', name: 'B', description: 'bee' }] }, config_options: [], available_commands: [] } as any)
check('modes-only agent: mode row shown', modesOnly.rows.length === 1 && modesOnly.rows[0].id === MODE_KEY && modesOnly.valueOf(MODE_KEY) === 'b' && modesOnly.summary === 'B')
check('modes-only agent: picking updates a copy', modesOnly.withValue(MODE_KEY, 'a').valueOf(MODE_KEY) === 'a' && modesOnly.valueOf(MODE_KEY) === 'b')
const grouped = AgentOptions.from({ modes: null, config_options: [
  { id: 'model', name: 'Model', category: 'model', kind: { type: 'select', current_value: 'x/2',
    options: [{ value: 'x/1', name: 'One' }, { value: 'x/2', name: 'Two' }, { value: 'y/3', name: 'Three' }],
    groups: [{ group: 'x', name: 'X', options: [{ value: 'x/1', name: 'One' }, { value: 'x/2', name: 'Two' }] }, { group: 'y', name: 'Y', options: [{ value: 'y/3', name: 'Three' }] }] } },
  { id: 'auto_approve', name: 'Auto-approve tools', category: null, kind: { type: 'boolean', current_value: true } },
  { id: 'future', name: 'Future', kind: { type: 'slider', current_value: 3 } },
  { id: 'empty', name: 'Empty', kind: { type: 'select', current_value: '', options: [], groups: [] } }
] } as any)
const gm = grouped.row('model')!
check('grouped select: each choice once, under its group', gm.choices.length === 3 && JSON.stringify(gm.groupNames) === '["X","Y"]' && gm.inGroup('X').length === 2 && gm.currentName === 'Two')
const gb = grouped.row('auto_approve')!
check('boolean option: On/Off carried as "true"/"false"', gb.current === 'true' && gb.has('true') && gb.has('false') && grouped.withValue('auto_approve', 'false').valueOf('auto_approve') === 'false')
check('unknown kind and empty select are not listed', grouped.row('future') === undefined && grouped.row('empty') === undefined && grouped.rows.length === 2)
const live = AgentOptions.from({ status: 'connected', modes: null, current_mode: null, config_options: null, available_commands: [], selectors_ready: false } as any)
check('snapshot of a connection still starting: no rows, not ready', live.rows.length === 0 && live.ready === false)
console.log(fail === 0 ? '\nALL PASS' : `\n${fail} FAILED`)
process.exit(fail === 0 ? 0 : 1)
