import { webview } from '@kit.ArkWeb'
import { util } from '@kit.ArkTS'
import { app } from '../store/AppState'
import { EventSocket, EventSocketListener } from '../net/EventSocket'
import { JObj, num, str, bool } from '../common/Json'
import { errorText } from '../net/ApiError'
import { L } from '../common/I18n'
import { sym, toast } from '../components/Common'

/** JS bridge object exposed to the xterm.js page as `codegTerm`. */
class TermBridge {
  owner: TerminalView

  constructor(owner: TerminalView) {
    this.owner = owner
  }

  input(data: string): void {
    this.owner.sendInput(data)
  }

  resize(cols: number, rows: number): void {
    this.owner.onResize(cols, rows)
  }

  ready(cols: number, rows: number): void {
    this.owner.onPageReady(cols, rows)
  }
}

class TermSocketListener implements EventSocketListener {
  owner: TerminalView

  constructor(owner: TerminalView) {
    this.owner = owner
  }

  onReady(): void {
    this.owner.onSocketReady()
  }

  onFrame(type: string, frame: JObj): void {
  }

  onChannel(channel: string, payload: JObj): void {
    this.owner.onChannel(channel, payload)
  }

  onClosed(reason: string): void {
    this.owner.onSocketClosed(reason)
  }
}

const KEYS: string[][] = [
  ['Esc', '\u001b'], ['Tab', '\t'], ['Ctrl-C', '\u0003'], ['Ctrl-D', '\u0004'], ['Ctrl-Z', '\u001a'],
  ['Ctrl-L', '\u000c'], ['↑', '\u001b[A'], ['↓', '\u001b[B'], ['←', '\u001b[D'], ['→', '\u001b[C'],
  ['|', '|'], ['~', '~'], ['/', '/'], ['-', '-']
]

/**
 * Terminal: PTY on the server, output over `/ws/events` (terminal://output/<id>),
 * input and resize over HTTP. xterm.js renders inside ArkWeb.
 */
@ComponentV2
export struct TerminalView {
  @Param cwd: string = ''
  @Local status: string = 'starting'
  @Local exited: boolean = false
  private controller: webview.WebviewController = new webview.WebviewController()
  private socket: EventSocket | null = null
  private terminalId: string = ''
  private spawned: boolean = false
  private pageReady: boolean = false
  private socketReady: boolean = false
  private cols: number = 80
  private rows: number = 24
  private lastSeq: number = -1
  private generation: number = -1
  private pending: string[] = []
  private disposed: boolean = false
  private bridge: TermBridge = new TermBridge(this)

  aboutToAppear(): void {
    this.terminalId = util.generateRandomUUID(false)
    this.openSocket()
  }

  aboutToDisappear(): void {
    this.disposed = true
    this.socket?.close()
    if (this.spawned) {
      app.api?.terminalKill(this.terminalId)
    }
  }

  openSocket(): void {
    const api = app.api
    if (api === null) {
      return
    }
    this.socketReady = false
    this.socket = new EventSocket(api.c, new TermSocketListener(this))
    this.socket.open()
  }

  onSocketReady(): void {
    this.socketReady = true
    this.maybeSpawn()
    if (this.spawned) {
      this.recover()
    }
  }

  onSocketClosed(reason: string): void {
    this.socketReady = false
    if (this.disposed || this.exited) {
      return
    }
    this.status = 'reconnecting'
    setTimeout((): void => {
      if (!this.disposed) {
        this.openSocket()
      }
    }, 1500)
  }

  onPageReady(cols: number, rows: number): void {
    this.cols = cols
    this.rows = rows
    this.pageReady = true
    this.flush()
    this.maybeSpawn()
  }

  onResize(cols: number, rows: number): void {
    if (cols === this.cols && rows === this.rows) {
      return
    }
    this.cols = cols
    this.rows = rows
    if (this.spawned) {
      app.api?.terminalResize(this.terminalId, cols, rows).catch(() => {
      })
    }
  }

  async maybeSpawn(): Promise<void> {
    const api = app.api
    if (this.spawned || !this.pageReady || !this.socketReady || api === null) {
      return
    }
    this.spawned = true
    try {
      const shell = await api.defaultShell()
      this.terminalId = await api.terminalSpawn(this.cwd, this.terminalId, shell)
      await api.terminalResize(this.terminalId, this.cols, this.rows)
      this.status = 'running'
    } catch (e) {
      this.spawned = false
      this.status = 'error'
      this.write(`\r\n\u001b[31m${errorText(e)}\u001b[0m\r\n`)
    }
  }

  /** After a reconnect, replay the server-side buffer and resume from its seq. */
  async recover(): Promise<void> {
    try {
      const s = await app.api!.terminalSnapshot(this.terminalId)
      if (!bool(s, 'exists')) {
        return
      }
      this.lastSeq = num(s, 'seq', -1)
      this.generation = num(s, 'generation', -1)
      this.js('termReset()')
      this.write(str(s, 'data'))
      this.status = bool(s, 'alive', true) ? 'running' : 'exited'
    } catch (e) {
      // Older servers lack terminal_snapshot.
      this.status = 'running'
    }
  }

  onChannel(channel: string, payload: JObj): void {
    if (channel === `terminal://output/${this.terminalId}`) {
      const seq = num(payload, 'seq', -1)
      const gen = num(payload, 'generation', -1)
      if (gen >= 0 && this.generation >= 0 && gen !== this.generation) {
        this.generation = gen
        this.lastSeq = -1
      }
      if (seq >= 0 && seq <= this.lastSeq) {
        return
      }
      if (seq >= 0) {
        this.lastSeq = seq
      }
      this.write(str(payload, 'data'))
    } else if (channel === `terminal://exit/${this.terminalId}`) {
      this.exited = true
      this.status = 'exited'
      this.write(`\r\n\u001b[2m[${L('process exited', '进程已退出')}]\u001b[0m\r\n`)
    }
  }

  /** WebviewController throws 17100001 until the Web component is attached. */
  js(script: string): void {
    try {
      this.controller.runJavaScript(script).catch(() => {
      })
    } catch (e) {
      // Not attached yet.
    }
  }

  write(data: string): void {
    if (data.length === 0) {
      return
    }
    if (!this.pageReady) {
      this.pending.push(data)
      return
    }
    this.js(`termWrite(${JSON.stringify(data)})`)
  }

  flush(): void {
    const p = this.pending
    this.pending = []
    p.forEach((d: string) => this.write(d))
  }

  sendInput(data: string): void {
    if (!this.spawned || this.exited) {
      return
    }
    app.api?.terminalWrite(this.terminalId, data).catch((e: Error) => {
      toast(errorText(e))
    })
  }

  restart(): void {
    if (this.spawned) {
      app.api?.terminalKill(this.terminalId)
    }
    this.terminalId = util.generateRandomUUID(false)
    this.spawned = false
    this.exited = false
    this.lastSeq = -1
    this.status = 'starting'
    this.js('termReset()')
    this.maybeSpawn()
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Circle().width(8).height(8).fill(this.status === 'running' ? $r('app.color.success') :
          this.status === 'error' || this.status === 'exited' ? $r('app.color.danger') : $r('app.color.warning'))
        Text(this.cwd).fontSize(11.5).fontFamily('monospace').fontColor($r('app.color.text3')).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph(sym('arrow_clockwise')).fontSize(16).fontColor([$r('app.color.text2')])
          .onClick(() => this.restart())
      }.padding({ left: 14, right: 14, top: 4, bottom: 6 }).width('100%')

      Web({ src: $rawfile('term/index.html'), controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .javaScriptProxy({
          object: this.bridge, name: 'codegTerm', methodList: ['input', 'resize', 'ready'],
          controller: this.controller
        })
        .backgroundColor('#0E1018')
        .layoutWeight(1)
        .width('100%')
        .onClick(() => {
          this.js('termFocus()')
        })

      Scroll() {
        Row({ space: 6 }) {
          ForEach(KEYS, (k: string[]) => {
            Text(k[0]).fontSize(13).fontFamily('monospace').fontColor($r('app.color.text'))
              .padding({ left: 12, right: 12, top: 8, bottom: 8 }).borderRadius(8)
              .backgroundColor($r('app.color.surface2'))
              .onClick(() => this.sendInput(k[1]))
          }, (k: string[]) => k[0])
        }.padding({ left: 8, right: 8, top: 6, bottom: 6 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .height('100%')
  }
}
