// Windowed history against a real codeg-server: newest window, then older pages until the start.
import { Api } from '@app/net/Api'
import { CodegClient } from '@app/net/CodegClient'
const host = process.env.CODEG_HOST ?? '127.0.0.1', port = process.env.CODEG_PORT ?? '3080'
const api = new Api(new CodegClient(`http://${host}:${port}`, process.env.CODEG_TOKEN ?? ''))
const convs = await api.conversations()
const big = convs.sort((a, b) => b.messageCount - a.messageCount).slice(0, 3)
let fail = 0
for (const c of big) {
  const t0 = Date.now()
  const d = await api.conversation(c.id, 80)
  let offset = d.turnsOffset, n = d.turns.length, pages = 0
  while (offset > 0) {
    const p = await api.conversationTurns(c.id, offset, 80)
    if (p.turnsOffset >= offset) { console.log(`FAIL conv ${c.id}: page did not move back (${p.turnsOffset})`); fail++; break }
    offset = p.turnsOffset; n += p.turns.length; pages++
  }
  const ok = n === d.turnsTotal
  if (!ok) fail++
  console.log(`${ok ? 'PASS' : 'FAIL'}  conv ${c.id}: first window ${d.turns.length}/${d.turnsTotal} turns, ${pages} older pages, ${n} total, ${Date.now() - t0} ms`)
}
if (fail > 0) process.exit(1)
