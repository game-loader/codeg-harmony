const stores: Map<string, Map<string, any>> = new Map()
export const preferences = {
  getPreferencesSync(_ctx: any, o: { name: string }) {
    if (!stores.has(o.name)) stores.set(o.name, new Map())
    const m = stores.get(o.name)!
    return {
      getSync(k: string, d: any) { return m.has(k) ? m.get(k) : d },
      putSync(k: string, v: any) { m.set(k, v) },
      deleteSync(k: string) { m.delete(k) },
      flush() { return Promise.resolve() },
      flushSync() {}
    }
  }
}
