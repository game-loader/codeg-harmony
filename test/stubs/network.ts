// Node stand-ins for @kit.NetworkKit, just enough for CodegClient and EventSocket.
export const http = {
  RequestMethod: { POST: 'POST' },
  HttpDataType: { STRING: 0 },
  createHttp() {
    const streamHandlers: Record<string, Function> = {}
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
      // Streamed download: chunks arrive as `dataReceive` events and the promise
      // yields the status code. The last chunk and `dataEnd` are delivered after
      // the promise settles, the least convenient order for the caller.
      on(ev: string, cb: Function) { streamHandlers[ev] = cb },
      off(ev: string) { delete streamHandlers[ev] },
      async requestInStream(url: string, o: any): Promise<number> {
        const res = await fetch(url, { method: 'POST', headers: o.header, body: o.extraData })
        const headers: Record<string, string> = {}
        res.headers.forEach((v: string, k: string) => { headers[k] = v })
        streamHandlers['headersReceive']?.(headers)
        const chunks: Uint8Array[] = []
        const reader = res.body!.getReader()
        for (;;) {
          const r = await reader.read()
          if (r.done) break
          chunks.push(r.value)
        }
        const last = chunks.pop()
        for (const c of chunks) streamHandlers['dataReceive']?.(c.buffer.slice(c.byteOffset, c.byteOffset + c.byteLength))
        setTimeout(() => {
          if (last !== undefined) streamHandlers['dataReceive']?.(last.buffer.slice(last.byteOffset, last.byteOffset + last.byteLength))
          streamHandlers['dataEnd']?.()
        }, 20)
        return res.status
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
