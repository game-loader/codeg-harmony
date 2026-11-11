import { asObj, parseJson, str } from '../common/Json'

export class ApiError extends Error {
  status: number
  code: string
  detail: string

  constructor(status: number, code: string, message: string, detail: string = '') {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.detail = detail
  }

  static fromResponse(status: number, body: string): ApiError {
    try {
      const o = asObj(parseJson(body))
      const msg = str(o, 'message', body.length > 0 ? body : `HTTP ${status}`)
      return new ApiError(status, str(o, 'code'), msg, str(o, 'detail'))
    } catch (e) {
      return new ApiError(status, '', body.length > 0 ? body.substring(0, 300) : `HTTP ${status}`)
    }
  }

  get display(): string {
    return this.detail.length > 0 ? this.detail : this.message
  }

  get isUnauthorized(): boolean {
    return this.status === 401
  }

  get isTurnInProgress(): boolean {
    return this.status === 409 || this.code === 'turn_in_progress'
  }

  get isStaleConnection(): boolean {
    const m = this.message.toLowerCase()
    return this.status === 404 && this.code.length > 0 && this.code !== 'not_implemented' ||
      this.code === 'connection_not_found' || this.code === 'unknown_connection' ||
      m.includes('connection not found')
  }

  get isNotFound(): boolean {
    return this.status === 404 || this.code === 'not_found'
  }

  get isNotGitRepo(): boolean {
    return this.code === 'not_a_git_repository'
  }

  get isGitAuth(): boolean {
    const m = (this.message + ' ' + this.detail).toLowerCase()
    return this.code === 'authentication_failed' || m.includes('authentication failed') ||
      m.includes('could not read username') || m.includes('could not read password') ||
      m.includes('logon failed')
  }

  get isUnsupported(): boolean {
    return this.status === 501 || this.code === 'not_implemented' ||
      (this.status === 404 && this.code.length === 0)
  }

  get isTransient(): boolean {
    return this.status === 0 || this.status >= 500 && !this.isStaleConnection
  }
}

export function errorText(e: Object | null | undefined): string {
  if (e instanceof ApiError) {
    return (e as ApiError).display
  }
  if (e instanceof Error) {
    return (e as Error).message
  }
  const o = asObj(e)
  const m = str(o, 'message')
  return m.length > 0 ? m : String(e)
}
