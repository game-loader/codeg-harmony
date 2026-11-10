import { preferences } from '@kit.ArkData'
import { asset } from '@kit.AssetStoreKit'
import { util } from '@kit.ArkTS'
import { common } from '@kit.AbilityKit'
import { asArr, asObj, num, str } from '../common/Json'

export class ServerProfile {
  id: string = ''
  name: string = ''
  url: string = ''
  createdAt: number = 0

  /** Normalised base URL: scheme added, trailing slash removed, path prefix kept. */
  static normalize(raw: string): string | null {
    let s = raw.trim()
    if (s.length === 0) {
      return null
    }
    if (!new RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://').test(s)) {
      s = 'http://' + s
    }
    const m = new RegExp('^(https?)://([^/?#@]+)(/[^?#]*)?$', 'i').exec(s)
    if (m === null) {
      return null
    }
    const hostPort = m[2]
    const pm = new RegExp(':(\\d+)$').exec(hostPort)
    if (pm !== null) {
      const port = Number(pm[1])
      if (port < 1 || port > 65535) {
        return null
      }
    }
    let path = m[3] ?? ''
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1)
    }
    return `${m[1].toLowerCase()}://${hostPort}${path}`
  }
}

const PREF = 'codeg_servers'
const KEY_LIST = 'servers'
const KEY_ACTIVE = 'active'

/** Server profiles live in preferences; bearer tokens live in the Asset store. */
export class ServerStore {
  private prefs: preferences.Preferences | null = null

  init(ctx: common.Context): void {
    this.prefs = preferences.getPreferencesSync(ctx, { name: PREF })
  }

  list(): ServerProfile[] {
    if (this.prefs === null) {
      return []
    }
    const raw = this.prefs.getSync(KEY_LIST, '[]') as string
    const out: ServerProfile[] = []
    for (const v of asArr(JSON.parse(raw) as Object)) {
      const o = asObj(v)
      const p = new ServerProfile()
      p.id = str(o, 'id')
      p.name = str(o, 'name')
      p.url = str(o, 'url')
      p.createdAt = num(o, 'createdAt')
      out.push(p)
    }
    return out
  }

  private saveList(list: ServerProfile[]): void {
    if (this.prefs === null) {
      return
    }
    this.prefs.putSync(KEY_LIST, JSON.stringify(list))
    this.prefs.flush()
  }

  activeId(): string {
    if (this.prefs === null) {
      return ''
    }
    return this.prefs.getSync(KEY_ACTIVE, '') as string
  }

  setActive(id: string): void {
    if (this.prefs === null) {
      return
    }
    this.prefs.putSync(KEY_ACTIVE, id)
    this.prefs.flush()
  }

  upsert(p: ServerProfile, token: string | null): void {
    const list = this.list()
    const i = list.findIndex((x: ServerProfile) => x.id === p.id)
    if (i >= 0) {
      list[i] = p
    } else {
      list.push(p)
    }
    this.saveList(list)
    if (token !== null) {
      this.setToken(p.id, token)
    }
  }

  remove(id: string): void {
    this.saveList(this.list().filter((x: ServerProfile) => x.id !== id))
    this.deleteToken(id)
    if (this.activeId() === id) {
      this.setActive('')
    }
  }

  private alias(id: string): Uint8Array {
    return new util.TextEncoder().encodeInto(`codeg.token.${id}`)
  }

  token(id: string): string {
    try {
      const q: asset.AssetMap = new Map()
      q.set(asset.Tag.ALIAS, this.alias(id))
      q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL)
      const res = asset.querySync(q)
      if (res.length > 0) {
        const secret = res[0].get(asset.Tag.SECRET) as Uint8Array
        return util.TextDecoder.create('utf-8').decodeToString(secret)
      }
    } catch (e) {
      // Fall through to the preferences fallback for devices without Asset.
    }
    if (this.prefs !== null) {
      return this.prefs.getSync(`token.${id}`, '') as string
    }
    return ''
  }

  setToken(id: string, token: string): void {
    this.deleteToken(id)
    try {
      const a: asset.AssetMap = new Map()
      a.set(asset.Tag.ALIAS, this.alias(id))
      a.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(token))
      a.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED)
      asset.addSync(a)
      return
    } catch (e) {
      // Asset is unavailable on some OpenHarmony builds.
    }
    if (this.prefs !== null) {
      this.prefs.putSync(`token.${id}`, token)
      this.prefs.flush()
    }
  }

  private deleteToken(id: string): void {
    try {
      const q: asset.AssetMap = new Map()
      q.set(asset.Tag.ALIAS, this.alias(id))
      asset.removeSync(q)
    } catch (e) {
      // Not found.
    }
    if (this.prefs !== null && this.prefs.hasSync(`token.${id}`)) {
      this.prefs.deleteSync(`token.${id}`)
      this.prefs.flush()
    }
  }
}

/** Small key-value settings shared across the app (theme, device id, selector prefs). */
export class AppPrefs {
  private static p: preferences.Preferences | null = null

  static init(ctx: common.Context): void {
    AppPrefs.p = preferences.getPreferencesSync(ctx, { name: 'codeg_app' })
  }

  static get(k: string, d: string = ''): string {
    if (AppPrefs.p === null) {
      return d
    }
    return AppPrefs.p.getSync(k, d) as string
  }

  static set(k: string, v: string): void {
    if (AppPrefs.p === null) {
      return
    }
    AppPrefs.p.putSync(k, v)
    AppPrefs.p.flush()
  }

  /** Writes and flushes synchronously; used from the crash handler. */
  static setSync(k: string, v: string): void {
    if (AppPrefs.p === null) {
      return
    }
    AppPrefs.p.putSync(k, v)
    AppPrefs.p.flushSync()
  }

  static deviceId(): string {
    let id = AppPrefs.get('device_id')
    if (id.length === 0) {
      id = util.generateRandomUUID(false)
      AppPrefs.set('device_id', id)
    }
    return id
  }
}
