import { Api } from '../net/Api'
import { errorText } from '../net/ApiError'
import { JObj, asObj, obj, str } from '../common/Json'
import { AppPrefs } from '../store/ServerStore'
import { AgentOptions, MODE_KEY } from './Interactive'

/** Id every agent gives its model option. */
const MODEL_ID: string = 'model'

/**
 * The mode and option values last picked on this device for one agent. New
 * sessions start with them: they go to `acp_connect`, which applies them
 * before the session reports its state. A resumed session keeps its own
 * settings, which the server stores and prefers over these.
 */
export class SelectorPrefs {
  mode: string = ''
  config: Map<string, string> = new Map()

  // "v2": the first layout was written by taps the UI never showed as selected.
  private static storeKey(agentType: string): string {
    return `selectors.v2.${agentType}`
  }

  static load(agentType: string): SelectorPrefs {
    const p = new SelectorPrefs()
    try {
      const o = asObj(JSON.parse(AppPrefs.get(SelectorPrefs.storeKey(agentType), '{}')) as Object)
      p.mode = str(o, 'mode')
      const cfg = obj(o, 'config')
      for (const k of Object.keys(cfg)) {
        const v = str(cfg, k)
        if (v.length > 0) {
          p.config.set(k, v)
        }
      }
    } catch (e) {
      // Corrupt entry; start without saved picks.
    }
    return p
  }

  static remember(agentType: string, key: string, value: string): void {
    const p = SelectorPrefs.load(agentType)
    if (key === MODE_KEY) {
      p.mode = value
    } else {
      p.config.set(key, value)
    }
    const o: JObj = { 'mode': p.mode, 'config': p.configValues ?? ({} as JObj) }
    AppPrefs.set(SelectorPrefs.storeKey(agentType), JSON.stringify(o))
  }

  /** Option values as `acp_connect` takes them; undefined when none are saved. */
  get configValues(): JObj | undefined {
    if (this.config.size === 0) {
      return undefined
    }
    const o: JObj = {} as JObj
    this.config.forEach((v: string, k: string) => {
      o[k] = v
    })
    return o
  }

  get model(): string {
    return this.config.get(MODEL_ID) ?? ''
  }

  /**
   * What the catalog probe applies before listing: the model only, since the
   * other lists (effort levels, fast mode) are the ones that depend on it.
   */
  get probeValues(): JObj | undefined {
    if (this.model.length === 0) {
      return undefined
    }
    const o: JObj = {} as JObj
    o[MODEL_ID] = this.model
    return o
  }
}

/** A catalog with this device's saved picks shown as selected, where the catalog still offers them. */
function applyPrefs(catalog: AgentOptions, prefs: SelectorPrefs): AgentOptions {
  let out = catalog
  for (const r of catalog.rows) {
    const saved = r.id === MODE_KEY ? prefs.mode : (prefs.config.get(r.id) ?? '')
    if (saved.length > 0 && saved !== r.current && r.has(saved)) {
      out = out.withValue(r.id, saved)
    }
  }
  return out
}

class Catalog {
  options: AgentOptions = new AgentOptions()
  at: number = 0
}

const CATALOG_TTL_MS: number = 5 * 60 * 1000
const catalogs: Map<string, Catalog> = new Map()

// The other lists depend on the model, so a catalog is kept per model.
function catalogKey(api: Api, agentType: string, workingDir: string | undefined, prefs: SelectorPrefs): string {
  return [api.c.baseUrl, agentType, workingDir ?? '', prefs.model].join('\n')
}

async function fetchCatalog(api: Api, agentType: string, workingDir: string | undefined,
  prefs: SelectorPrefs): Promise<AgentOptions> {
  // The server starts a throwaway agent, selects the saved model as a real
  // launch would, and reports the option lists that result.
  const fresh = AgentOptions.from(await api.describeAgentOptions(agentType, workingDir, prefs.probeValues))
  const c = new Catalog()
  c.options = fresh
  c.at = Date.now()
  catalogs.set(catalogKey(api, agentType, workingDir, prefs), c)
  return fresh
}

/** The agent's option catalog (cached), for callers that only need its slash commands. */
export async function agentCatalog(api: Api, agentType: string, workingDir?: string): Promise<AgentOptions> {
  const prefs = SelectorPrefs.load(agentType)
  const hit = catalogs.get(catalogKey(api, agentType, workingDir, prefs))
  if (hit !== undefined) {
    return hit.options
  }
  return await fetchCatalog(api, agentType, workingDir, prefs)
}

/**
 * State behind the mode / model rows. Before a session has a connection it
 * shows the agent's catalog under the saved picks (`prepareDraft`, `pick`).
 * Once the session is connected, SessionController feeds it the session's
 * real state (`adoptLive`) and applies picks itself.
 */
@ObservedV2
export class AgentOptionsModel {
  @Trace options: AgentOptions | null = null
  /** Bumped on every change; row keys include it, so the rows are redrawn. */
  @Trace rev: number = 0
  /** idle | loading (reading the catalog) | connecting (starting the session's agent) | ready | error */
  @Trace phase: string = 'idle'
  /** Why loading failed (phase `error`), or why the last change did not apply (phase `ready`). */
  @Trace error: string = ''
  /** Row whose change is being applied; empty when none. */
  @Trace applying: string = ''
  private api: Api | null = null
  private agentType: string = ''
  private workingDir: string | undefined = undefined
  private seq: number = 0

  get busy(): boolean {
    return this.phase === 'loading' || this.phase === 'connecting'
  }

  /** True while a tap must not start another change. */
  get locked(): boolean {
    return this.busy || this.applying.length > 0
  }

  show(o: AgentOptions | null): void {
    this.options = o
    this.rev++
  }

  setApplying(key: string): void {
    this.applying = key
    if (key.length > 0) {
      this.error = ''
    }
    this.rev++
  }

  private setPhase(phase: string): void {
    this.phase = phase
    this.rev++
  }

  /** Shows what a new session of `agentType` in `workingDir` would start with. */
  async prepareDraft(api: Api, agentType: string, workingDir?: string, force: boolean = false): Promise<void> {
    if (this.agentType !== agentType) {
      this.show(null)
    }
    this.api = api
    this.agentType = agentType
    this.workingDir = workingDir
    this.setApplying('')
    await this.loadCatalog(force, false)
  }

  private async loadCatalog(force: boolean, quiet: boolean): Promise<void> {
    const api = this.api
    if (api === null) {
      return
    }
    const seq = ++this.seq
    const agentType = this.agentType
    const workingDir = this.workingDir
    const prefs = SelectorPrefs.load(agentType)
    const hit = force ? undefined : catalogs.get(catalogKey(api, agentType, workingDir, prefs))
    this.error = ''
    if (hit !== undefined) {
      this.show(applyPrefs(hit.options, prefs))
      this.setPhase('ready')
      if (Date.now() - hit.at < CATALOG_TTL_MS) {
        return
      }
      // Stale: keep showing it and refresh behind it.
    } else if (!quiet) {
      this.setPhase('loading')
    }
    try {
      const fresh = await fetchCatalog(api, agentType, workingDir, prefs)
      if (seq !== this.seq) {
        return
      }
      this.show(applyPrefs(fresh, SelectorPrefs.load(agentType)))
      this.setPhase('ready')
    } catch (e) {
      if (seq !== this.seq) {
        return
      }
      // With lists already on screen (a cached catalog, or those of the
      // previous model), keep them; only an empty view reports the failure.
      if (this.options !== null) {
        this.setPhase('ready')
        return
      }
      this.error = errorText(e)
      this.setPhase('error')
    }
  }

  /** A pick for a session that has not started: remembered, and applied when the session connects. */
  async pick(key: string, value: string): Promise<void> {
    const cur = this.options
    if (cur === null || this.locked || cur.valueOf(key) === value) {
      return
    }
    SelectorPrefs.remember(this.agentType, key, value)
    this.show(cur.withValue(key, value))
    if (key !== MODEL_ID) {
      return
    }
    // The other lists can change with the model, so read the catalog for the new one.
    this.setApplying(key)
    await this.loadCatalog(false, true)
    this.setApplying('')
  }

  // Updates pushed by the session's live connection.

  private live(): AgentOptions {
    const cur = this.options
    return cur !== null ? cur.copy() : new AgentOptions()
  }

  liveModes(state: JObj): void {
    const o = this.live()
    o.setModes(state)
    this.show(o)
  }

  liveMode(modeId: string): void {
    const o = this.live()
    o.currentMode = modeId
    this.show(o)
  }

  liveConfigs(list: Object[]): void {
    const o = this.live()
    o.setConfigs(list)
    this.show(o)
  }

  liveCommands(list: Object[]): void {
    const o = this.live()
    o.setCommands(list)
    this.show(o)
  }

  liveReady(): void {
    const o = this.live()
    o.ready = true
    this.show(o)
    if (this.phase === 'connecting') {
      this.setPhase('ready')
    }
  }

  /** The session's agent is being started (or found) to read its settings. */
  connecting(): void {
    this.seq++
    this.error = ''
    this.setPhase('connecting')
  }

  /** The settings could not be read. */
  fail(message: string): void {
    this.error = message
    this.setPhase('error')
  }

  /** A change did not apply: say why next to the options, which stay usable. */
  reject(message: string): void {
    this.error = message
    if (this.busy) {
      this.setPhase(this.options !== null ? 'ready' : 'error')
    } else {
      this.rev++
    }
  }

  /** The session's real state, from its live connection. */
  adoptLive(o: AgentOptions): void {
    this.seq++
    const cur = this.options
    if (!o.ready && o.rows.length === 0 && cur !== null) {
      // The connection has not reported anything yet: keep what is shown.
      const keep = cur.copy()
      keep.ready = false
      this.show(keep)
    } else {
      this.show(o)
    }
    this.error = ''
    this.setPhase(o.ready ? 'ready' : 'connecting')
  }
}
