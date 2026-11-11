// Local stand-in for codeg-server: the handful of commands the options flow uses,
// with the wire shapes of the Rust types (LiveSessionSnapshot, AcpEvent, ws_attach::ServerMsg).
import http from 'node:http'
import { randomUUID } from 'node:crypto'
import { createReadStream, existsSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { WebSocketServer } from 'ws'

const sel = (id, name, category, current, values) => ({
  id, name, description: null, category,
  kind: { type: 'select', current_value: current, options: values.map(v => ({ value: v, name: v.toUpperCase(), description: null })), groups: [] },
  recommended_value: null
})
const freshConfig = () => [
  sel('mode', 'Mode', 'mode', 'auto', ['default', 'plan', 'auto']),
  sel('model', 'Model', 'model', 'opus', ['opus', 'sonnet', 'haiku', 'locked']),
  sel('effort', 'Effort', 'thought_level', 'medium', ['low', 'medium', 'high'])
]
const freshModes = () => ({ current_mode_id: 'auto', available_modes: ['default', 'plan', 'auto'].map(id => ({ id, name: id.toUpperCase(), description: null })) })

export async function startFake() {
  const f = {
    conns: new Map(), stored: new Map(), log: [], sockets: new Set(), seq: 0,
    readyDelayMs: 600, setDelayMs: 150, failConnect: 0,
    modesOnly: false, // an agent that publishes modes but no config options
    dropDownloadAfter: 0, // cut the connection after this many bytes of a download
    count(cmd) { return f.log.filter(l => l.cmd === cmd).length },
    last(cmd) { return [...f.log].reverse().find(l => l.cmd === cmd)?.body }
  }
  const snapshot = c => ({
    connection_id: c.id, conversation_id: null, folder_id: null, status: c.status, external_id: c.external_id,
    live_message: null, active_tool_calls: [], pending_permission: null,
    feedback_tool_available: false, native_steering_available: false,
    modes: c.ready ? c.modes : null, current_mode: c.ready ? c.modes.current_mode_id : null,
    config_options: c.ready ? c.config : null, prompt_capabilities: null, usage: null,
    fork_supported: false, available_commands: c.ready ? [{ name: 'review', description: 'Review code', input_hint: null }] : [],
    selectors_ready: c.ready, config_stale: false
  })
  const emit = (c, type, fields) => {
    const envelope = { seq: ++f.seq, connection_id: c.id, type, ...fields }
    for (const ws of f.sockets) for (const [sub, cid] of ws.subs) if (cid === c.id) ws.send(JSON.stringify({ type: 'event', subscription_id: sub, envelope }))
  }
  const persist = c => f.stored.set(c.external_id, { mode_id: c.modes.current_mode_id, config_values: Object.fromEntries(c.config.map(o => [o.id, o.kind.current_value])) })
  const setValue = (c, id, value) => {
    if (id === 'mode' && c.config.length === 0) { if (!c.modes.available_modes.some(m => m.id === value)) return false; c.modes.current_mode_id = value; return true }
    const o = c.config.find(x => x.id === id)
    if (!o || !o.kind.options.some(x => x.value === value)) return false
    o.kind.current_value = value
    if (id === 'mode') c.modes.current_mode_id = value
    return true
  }
  f.reclaim = id => {
    const c = f.conns.get(id)
    if (!c) return
    f.conns.delete(id)
    for (const ws of f.sockets) for (const [sub, cid] of [...ws.subs]) if (cid === id) { ws.subs.delete(sub); ws.send(JSON.stringify({ type: 'detached', subscription_id: sub, reason: 'connection_gone' })) }
  }
  f.pushFromElsewhere = (id, cfgId, value) => { const c = f.conns.get(id); setValue(c, cfgId, value); persist(c); emit(c, 'session_config_options', { config_options: c.config }); if (cfgId === 'mode') emit(c, 'mode_changed', { mode_id: value }) }

  const handlers = {
    get_folder_conversation: b => ({ summary: { id: b.conversationId, folder_id: 1, title: 'Existing', agent_type: 'claude_code', status: 'pending_review', external_id: 'sess-1', message_count: 4, created_at: '2026-11-01T00:00:00Z', updated_at: '2026-11-01T00:00:00Z' }, turns: [] }),
    acp_find_connection_for_conversation: b => { const c = [...f.conns.values()].find(x => x.external_id === b.sessionId); return c ? { connection_id: c.id, event_seq: f.seq } : null },
    acp_describe_agent_options: () => ({ modes: freshModes(), config_options: f.modesOnly ? [] : freshConfig(), available_commands: [], prompt_capabilities: null, unapplied_config_ids: [] }),
    acp_connect: b => {
      if (f.failConnect > 0) { f.failConnect--; throw new Error('failed to spawn agent: boom') }
      const c = { id: randomUUID(), status: 'connected', ready: false, external_id: b.sessionId ?? randomUUID(), modes: freshModes(), config: f.modesOnly ? [] : freshConfig() }
      // Client defaults first, then the session's own stored selectors over them (session_selector_service::merge_connect_prefs).
      const stored = b.sessionId ? f.stored.get(b.sessionId) : undefined
      const values = { ...(b.preferredConfigValues ?? {}), ...(stored?.config_values ?? {}) }
      const mode = stored?.mode_id ?? b.preferredModeId
      if (mode) setValue(c, 'mode', mode)
      for (const [k, v] of Object.entries(values)) setValue(c, k, v)
      f.conns.set(c.id, c)
      setTimeout(() => { if (!f.conns.has(c.id)) return; c.ready = true; persist(c); emit(c, 'session_modes', { modes: c.modes }); emit(c, 'session_config_options', { config_options: c.config }); emit(c, 'selectors_ready', {}) }, f.readyDelayMs)
      return c.id
    },
    acp_get_session_snapshot: b => { const c = f.conns.get(b.connectionId); return c ? snapshot(c) : null },
    acp_set_config_option: b => {
      const c = f.conns.get(b.connectionId)
      if (!c) throw new Error(`connection not found: ${b.connectionId}`)
      setTimeout(() => {
        if (b.valueId === 'locked') {
          // The agent answers with the list it actually adopted (unchanged) and codeg reports the mismatch.
          emit(c, 'config_option_rejected', { config_id: b.configId, option_name: 'Model', requested: 'LOCKED', actual: c.config.find(o => o.id === b.configId).kind.current_value.toUpperCase(), requested_value: 'locked', actual_value: c.config.find(o => o.id === b.configId).kind.current_value })
        } else {
          setValue(c, b.configId, b.valueId); persist(c)
          if (b.configId === 'mode') emit(c, 'mode_changed', { mode_id: b.valueId })
        }
        emit(c, 'session_config_options', { config_options: c.config })
      }, f.setDelayMs)
      return null
    },
    acp_set_mode: b => { const c = f.conns.get(b.connectionId); if (!c) throw new Error(`connection not found: ${b.connectionId}`); setTimeout(() => { setValue(c, 'mode', b.modeId); persist(c); emit(c, 'mode_changed', { mode_id: b.modeId }) }, f.setDelayMs); return null },
    acp_disconnect: b => { f.reclaim(b.connectionId); return null },
    // CreateChatConversationResult is camelCase; the FolderDetail inside it keeps snake_case.
    create_chat_conversation: () => ({ conversationId: 9, folderId: 4, folder: { id: 4, name: 'Chat', path: '/data/chat-sessions/2026-11-11/abc', git_branch: null, default_agent_type: null, last_opened_at: '2026-11-11T00:00:00Z', sort_order: 0, color: '', parent_id: null, kind: 'chat', alias: null } }),
    acp_prompt: () => null,
    workspace_download_ticket: b => ({ ticket: 'tkt123', url: '/api/workspace_download/tkt123', filename: b.path.split('/').pop(), expiresAt: '0' })
  }
  const server = http.createServer((req, res) => {
    let raw = ''
    req.on('data', d => { raw += d })
    req.on('end', () => {
      const cmd = req.url.replace('/api/', '')
      const body = raw ? JSON.parse(raw) : {}
      f.log.push({ cmd, body })
      if (cmd === 'download_workspace_file') {
        // Streams the bytes as application/octet-stream with a Content-Length, like the real handler.
        const target = join(body.rootPath, body.path)
        if (!existsSync(target) || !statSync(target).isFile()) {
          res.statusCode = 404
          res.setHeader('Content-Type', 'application/json')
          res.end(JSON.stringify({ code: 'not_found', message: 'File does not exist' }))
          return
        }
        res.setHeader('Content-Type', 'application/octet-stream')
        res.setHeader('Content-Length', String(statSync(target).size))
        if (f.dropDownloadAfter > 0) {
          createReadStream(target, { end: f.dropDownloadAfter - 1 }).on('data', d => res.write(d)).on('end', () => setTimeout(() => res.destroy(), 50))
        } else {
          createReadStream(target).pipe(res)
        }
        return
      }
      res.setHeader('Content-Type', 'application/json')
      try {
        if (!handlers[cmd]) { res.statusCode = 404; res.end('{}'); return }
        res.end(JSON.stringify(handlers[cmd](body)))
      } catch (e) {
        res.statusCode = 500
        res.end(JSON.stringify({ code: 'task_execution_failed', message: e.message }))
      }
    })
  })
  const wss = new WebSocketServer({ server, path: '/ws/events', handleProtocols: () => 'codeg-events' })
  wss.on('connection', ws => {
    ws.subs = new Map(); f.sockets.add(ws)
    ws.send(JSON.stringify({ channel: '__ready__', payload: {} }))
    ws.on('close', () => f.sockets.delete(ws))
    ws.on('message', m => {
      const o = JSON.parse(m.toString())
      if (o.action === 'attach') {
        const c = f.conns.get(o.connection_id)
        if (!c) { ws.send(JSON.stringify({ type: 'detached', subscription_id: o.subscription_id, reason: 'connection_gone' })); return }
        ws.subs.set(o.subscription_id, c.id)
        ws.send(JSON.stringify({ type: 'snapshot', subscription_id: o.subscription_id, connection_id: c.id, snapshot: snapshot(c), event_seq: f.seq }))
      } else if (o.action === 'detach') ws.subs.delete(o.subscription_id)
      else if (o.action === 'ping') ws.send(JSON.stringify({ type: 'pong' }))
    })
  })
  await new Promise(r => server.listen(0, '127.0.0.1', r))
  f.url = `http://127.0.0.1:${server.address().port}`
  f.stop = () => { for (const ws of f.sockets) ws.terminate(); wss.close(); server.close() }
  return f
}
