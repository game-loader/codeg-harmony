import { i18n } from '@kit.LocalizationKit'

let zh: boolean = false

export function initLocale(): void {
  try {
    const lang = i18n.System.getSystemLanguage()
    zh = lang.startsWith('zh')
  } catch (e) {
    zh = false
  }
}

export function isZh(): boolean {
  return zh
}

export function setZh(v: boolean): void {
  zh = v
}

/** Picks the English or Simplified Chinese string; the iOS client ships the same two. */
export function L(en: string, cn: string): string {
  return zh ? cn : en
}

export function langCode(): string {
  return zh ? 'zh-CN' : 'en'
}

export function relativeTime(ms: number): string {
  if (ms <= 0) {
    return ''
  }
  const d = (Date.now() - ms) / 1000
  if (d < 60) {
    return L('just now', '刚刚')
  }
  if (d < 3600) {
    return L(`${Math.floor(d / 60)}m ago`, `${Math.floor(d / 60)} 分钟前`)
  }
  if (d < 86400) {
    return L(`${Math.floor(d / 3600)}h ago`, `${Math.floor(d / 3600)} 小时前`)
  }
  if (d < 86400 * 7) {
    return L(`${Math.floor(d / 86400)}d ago`, `${Math.floor(d / 86400)} 天前`)
  }
  const dt = new Date(ms)
  return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())}`
}

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

export function formatBytes(n: number): string {
  if (n < 1024) {
    return `${n} B`
  }
  if (n < 1024 * 1024) {
    return `${(n / 1024).toFixed(1)} KB`
  }
  if (n < 1024 * 1024 * 1024) {
    return `${(n / 1024 / 1024).toFixed(1)} MB`
  }
  return `${(n / 1024 / 1024 / 1024).toFixed(1)} GB`
}

export function formatTokens(n: number): string {
  if (n >= 1000000) {
    return `${(n / 1000000).toFixed(1)}M`
  }
  if (n >= 1000) {
    return `${(n / 1000).toFixed(1)}k`
  }
  return `${n}`
}
