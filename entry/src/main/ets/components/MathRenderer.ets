import { webview } from '@kit.ArkWeb'

export class MathImage {
  png: string = ''
  w: number = 0
  h: number = 0
  failed: boolean = false
}

class MathJob {
  id: number = 0
  key: string = ''
  tex: string = ''
  display: boolean = false
  color: string = ''
  em: number = 16
}

const SCALE = 3
const CACHE_MAX = 800

/**
 * TeX → PNG via MathJax running in one hidden ArkWeb page (MathHost). Views
 * read `version` so they re-render when a formula they asked for arrives;
 * until then they show the TeX source.
 */
@ObservedV2
export class MathRenderer {
  @Trace version: number = 0
  /** loading | ready | unavailable; plus the last page error, shown in Settings. */
  @Trace status: string = 'loading'
  @Trace lastError: string = ''
  rendered: number = 0
  failed: number = 0
  controller: webview.WebviewController = new webview.WebviewController()
  private ready: boolean = false
  private nextId: number = 1
  private cache: Map<string, MathImage> = new Map()
  private inflight: Map<number, MathJob> = new Map()
  private queued: MathJob[] = []
  private pendingKeys: Set<string> = new Set()
  private bumpScheduled: boolean = false

  static keyOf(tex: string, display: boolean, color: string, em: number): string {
    return `${display ? 'D' : 'I'}|${color}|${em}|${tex}`
  }

  /** Cached image, or undefined after scheduling a render. Safe to call during build. */
  get(tex: string, display: boolean, color: string, em: number): MathImage | undefined {
    const key = MathRenderer.keyOf(tex, display, color, em)
    const hit = this.cache.get(key)
    if (hit !== undefined || this.pendingKeys.has(key)) {
      return hit
    }
    this.pendingKeys.add(key)
    const job = new MathJob()
    job.id = this.nextId++
    job.key = key
    job.tex = tex
    job.display = display
    job.color = color
    job.em = em
    this.queued.push(job)
    // Never touch the page synchronously from inside a build pass.
    setTimeout((): void => {
      this.pump()
    }, 0)
    return undefined
  }

  has(tex: string, display: boolean, color: string, em: number): boolean {
    return this.cache.has(MathRenderer.keyOf(tex, display, color, em))
  }

  private pump(): void {
    if (!this.ready) {
      return
    }
    const jobs = this.queued
    this.queued = []
    for (const j of jobs) {
      this.inflight.set(j.id, j)
      const script = `renderOne(${j.id}, ${JSON.stringify(j.tex)}, ${j.display}, ${JSON.stringify(j.color)}, ${j.em}, ${SCALE})`
      try {
        this.controller.runJavaScript(script).catch(() => {
          this.finish(j.id, null)
        })
      } catch (e) {
        // Page detached; retry when it reports ready again.
        this.inflight.delete(j.id)
        this.queued.push(j)
        this.ready = false
        return
      }
    }
  }

  onReady(): void {
    this.status = 'ready'
    this.ready = true
    this.pump()
  }

  finish(id: number, img: MathImage | null): void {
    const j = this.inflight.get(id)
    if (j === undefined) {
      return
    }
    this.inflight.delete(id)
    this.pendingKeys.delete(j.key)
    let out = img
    if (img !== null) {
      this.rendered++
    } else {
      this.failed++
    }
    if (out === null) {
      out = new MathImage()
      out.failed = true
    }
    if (this.cache.size >= CACHE_MAX) {
      const first = this.cache.keys().next()
      if (!first.done) {
        this.cache.delete(first.value)
      }
    }
    this.cache.set(j.key, out)
    if (!this.bumpScheduled) {
      // Coalesce a burst of results into one re-render.
      this.bumpScheduled = true
      setTimeout((): void => {
        this.bumpScheduled = false
        this.version++
      }, 16)
    }
  }
}

export const math: MathRenderer = new MathRenderer()

class MathResult {
  png: string = ''
  w: number = 0
  h: number = 0
}

class MathBridge {
  ready(): void {
    math.onReady()
  }

  done(id: number, json: string): void {
    try {
      const r = JSON.parse(json) as MathResult
      const img = new MathImage()
      img.png = r.png
      img.w = r.w
      img.h = r.h
      math.finish(id, img.png.length > 0 && img.w > 0 ? img : null)
    } catch (e) {
      math.finish(id, null)
    }
  }

  fail(id: number, reason: string): void {
    if (reason !== 'tex') {
      math.lastError = reason
    }
    math.finish(id, null)
  }
}

/** Mount once near the root. Invisible and inert. */
@ComponentV2
export struct MathHost {
  private bridge: MathBridge = new MathBridge()

  aboutToAppear(): void {
    setTimeout((): void => {
      if (math.status === 'loading') {
        math.status = 'unavailable'
      }
    }, 20000)
  }

  build() {
    Web({ src: $rawfile('math/index.html'), controller: math.controller })
      .javaScriptAccess(true)
      .fileAccess(true)
      .javaScriptProxy({
        object: this.bridge, name: 'codegMath', methodList: ['ready', 'done', 'fail'],
        controller: math.controller
      })
      .onConsole((e: OnConsoleEvent) => {
        if (e.message.getMessageLevel() === MessageLevel.Error) {
          math.lastError = e.message.getMessage().substring(0, 300)
        }
        return false
      })
      .onErrorReceive((e: OnErrorReceiveEvent) => {
        math.lastError = `load: ${e.error.getErrorInfo()} ${e.request.getRequestUrl()}`.substring(0, 300)
      })
      .onPageEnd(() => {
        // The page may have finished MathJax startup before the proxy existed.
        math.controller.runJavaScript('window.mathReady === true').then((v: string) => {
          if (v === 'true') {
            math.onReady()
          }
        }).catch(() => {
        })
      })
      .width(320)
      .height(200)
      .opacity(0)
      .hitTestBehavior(HitTestMode.None)
  }
}
