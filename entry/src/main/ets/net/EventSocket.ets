import { webSocket } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { CodegClient } from './CodegClient'
import { JObj, asObj, parseJson, str } from '../common/Json'

export interface EventSocketListener {
  onReady(): void
  /** Attach-protocol frame: snapshot / replay / event / detached / pong. */
  onFrame(type: string, frame: JObj): void
  /** Legacy firehose frame such as terminal output. */
  onChannel(channel: string, payload: JObj): void
  onClosed(reason: string): void
}

/**
 * One `/ws/events` socket. Auth rides in the subprotocol list, and an
 * app-level ping every 20 s detects dead sockets on mobile networks.
 */
export class EventSocket {
  private ws: webSocket.WebSocket | null = null
  private pingTimer: number = -1
  private closed: boolean = false
  private readyFired: boolean = false
  private readyTimer: number = -1
  private listener: EventSocketListener
  private client: CodegClient

  constructor(client: CodegClient, listener: EventSocketListener) {
    this.client = client
    this.listener = listener
  }

  open(): void {
    const ws = webSocket.createWebSocket()
    this.ws = ws
    ws.on('open', () => {
      this.pingTimer = setInterval(() => {
        this.sendObj({ 'action': 'ping' } as JObj)
      }, 20000)
      // Older servers never send __ready__; fall back after a bounded wait.
      this.readyTimer = setTimeout(() => {
        this.fireReady()
      }, 3000)
    })
    ws.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
      if (err || typeof data !== 'string') {
        return
      }
      this.handle(data as string)
    })
    ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      this.finish(value?.reason ?? 'closed')
    })
    ws.on('error', (err: BusinessError) => {
      this.finish(err?.message ?? 'error')
    })
    ws.connect(this.client.wsUrl, {
      protocol: this.client.wsProtocol,
      header: { 'Sec-WebSocket-Protocol': this.client.wsProtocol }
    }).catch((e: BusinessError) => {
      this.finish(e?.message ?? 'connect failed')
    })
  }

  private fireReady(): void {
    if (this.readyFired || this.closed) {
      return
    }
    this.readyFired = true
    clearTimeout(this.readyTimer)
    this.listener.onReady()
  }

  private handle(text: string): void {
    let o: JObj
    try {
      o = asObj(parseJson(text))
    } catch (e) {
      return
    }
    const channel = str(o, 'channel')
    if (channel.length > 0) {
      if (channel === '__ready__') {
        this.fireReady()
      } else {
        this.listener.onChannel(channel, asObj(o['payload']))
      }
      return
    }
    const type = str(o, 'type')
    if (type.length > 0) {
      this.listener.onFrame(type, o)
    }
  }

  private finish(reason: string): void {
    if (this.closed) {
      return
    }
    this.closed = true
    clearInterval(this.pingTimer)
    clearTimeout(this.readyTimer)
    this.listener.onClosed(reason)
  }

  get isOpen(): boolean {
    return this.ws !== null && !this.closed
  }

  sendObj(o: JObj): void {
    if (this.ws === null || this.closed) {
      return
    }
    this.ws.send(JSON.stringify(o)).catch(() => {
    })
  }

  attach(subscriptionId: string, connectionId: string): void {
    this.sendObj({ 'action': 'attach', 'subscription_id': subscriptionId, 'connection_id': connectionId } as JObj)
  }

  detach(subscriptionId: string): void {
    this.sendObj({ 'action': 'detach', 'subscription_id': subscriptionId } as JObj)
  }

  close(): void {
    const ws = this.ws
    this.closed = true
    clearInterval(this.pingTimer)
    clearTimeout(this.readyTimer)
    if (ws !== null) {
      ws.close().catch(() => {
      })
      ws.off('open')
      ws.off('message')
      ws.off('close')
      ws.off('error')
    }
    this.ws = null
  }
}
