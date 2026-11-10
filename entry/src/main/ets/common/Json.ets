// Lenient JSON accessors. Server responses are snake_case and fields may be
// missing or null on older servers, so every read has a default.
export type JObj = Record<string, Object>

export function parseJson(text: string): Object | null {
  if (text.trim().length === 0) {
    return null
  }
  return JSON.parse(text) as Object | null
}

export function isObj(v: Object | null | undefined): boolean {
  return v !== null && v !== undefined && typeof v === 'object' && !Array.isArray(v)
}

export function asObj(v: Object | null | undefined): JObj {
  if (isObj(v)) {
    return v as JObj
  }
  return {} as JObj
}

export function asArr(v: Object | null | undefined): Object[] {
  if (v !== null && v !== undefined && Array.isArray(v)) {
    return v as Object[]
  }
  return []
}

export function has(o: JObj, k: string): boolean {
  const v = o[k]
  return v !== null && v !== undefined
}

export function str(o: JObj, k: string, d: string = ''): string {
  const v = o[k]
  if (typeof v === 'string') {
    return v as string
  }
  if (typeof v === 'number' || typeof v === 'boolean') {
    return String(v)
  }
  return d
}

export function optStr(o: JObj, k: string): string | undefined {
  const v = o[k]
  if (typeof v === 'string') {
    return v as string
  }
  return undefined
}

export function num(o: JObj, k: string, d: number = 0): number {
  const v = o[k]
  if (typeof v === 'number') {
    return v as number
  }
  if (typeof v === 'string') {
    const n = Number(v as string)
    return isNaN(n) ? d : n
  }
  return d
}

export function optNum(o: JObj, k: string): number | undefined {
  const v = o[k]
  if (typeof v === 'number') {
    return v as number
  }
  return undefined
}

export function bool(o: JObj, k: string, d: boolean = false): boolean {
  const v = o[k]
  if (typeof v === 'boolean') {
    return v as boolean
  }
  return d
}

export function obj(o: JObj, k: string): JObj {
  return asObj(o[k])
}

export function arr(o: JObj, k: string): Object[] {
  return asArr(o[k])
}

export function strArr(o: JObj, k: string): string[] {
  const out: string[] = []
  for (const v of arr(o, k)) {
    if (typeof v === 'string') {
      out.push(v as string)
    }
  }
  return out
}

/** Serialises a value that may be an object, array or string for display. */
export function pretty(v: Object | null | undefined): string {
  if (v === null || v === undefined) {
    return ''
  }
  if (typeof v === 'string') {
    return v as string
  }
  return JSON.stringify(v, null, 2)
}

export function parseDate(s: string): number {
  if (s.length === 0) {
    return 0
  }
  let t = Date.parse(s)
  if (isNaN(t)) {
    t = Date.parse(s.replace(new RegExp('\\.\\d+'), ''))
  }
  return isNaN(t) ? 0 : t
}
