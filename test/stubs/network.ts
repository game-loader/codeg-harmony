// Node stand-ins for @kit.NetworkKit, just enough for CodegClient and EventSocket.
export const http = {
  RequestMethod: { POST: 'POST' },
  HttpDataType: { STRING: 0 },
  createHttp() {
    return {
      async request(url: string, o: any) {
        const ctl = new AbortController()
        const timer = setTimeout(() => ctl.abort(), o.readTimeout ?? 120000)
        try {
          const res = await fetch(url, { method: 'POST', headers: o.header, body: o.extraData, signal: ctl.signal })
          return { responseCode: res.status, result: await res.text() }
        } finally {
          clearTimeout(timer)
        }
      },
      destroy() {}
    }
  }
}
export const webSocket = {
  createWebSocket() {
    const handlers: Record<string, Function> = {}
    let ws: any = null
    return {
      on(ev: string, cb: Function) { handlers[ev] = cb },
      off(ev: string) { delete handlers[ev] },
      connect(url: string, o: any): Promise<boolean> {
        const protocols = String(o.protocol).split(',').map((s: string) => s.trim())
        ws = new (globalThis as any).WebSocket(url, protocols)
        ws.addEventListener('open', () => handlers['open']?.(undefined, {}))
        ws.addEventListener('message', (m: any) => handlers['message']?.(undefined, m.data))
        ws.addEventListener('close', (c: any) => handlers['close']?.(undefined, { code: c.code, reason: c.reason }))
        ws.addEventListener('error', () => handlers['error']?.({ message: 'ws error' }))
        return Promise.resolve(true)
      },
      send(d: string): Promise<boolean> { ws.send(d); return Promise.resolve(true) },
      close(): Promise<boolean> { try { ws?.close() } catch (e) {} return Promise.resolve(true) }
    }
  }
}
