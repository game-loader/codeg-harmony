import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { ApiError } from './ApiError'
import { JObj, parseJson } from '../common/Json'

export class Timeouts {
  connect: number = 30000
  read: number = 120000

  constructor(connect: number, read: number) {
    this.connect = connect
    this.read = read
  }

  static readonly DEFAULT: Timeouts = new Timeouts(30000, 120000)
  static readonly LIST: Timeouts = new Timeouts(15000, 60000)
  static readonly PROBE: Timeouts = new Timeouts(90000, 150000)
  static readonly INSTALL: Timeouts = new Timeouts(120000, 900000)
}

export class UploadFile {
  name: string = ''
  mimeType: string = 'application/octet-stream'
  filePath: string = ''
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms)
  })
}

/**
 * Every server command is `POST {base}/api/{command}` with a camelCase JSON
 * body and a bearer token; responses are snake_case JSON.
 */
export class CodegClient {
  readonly baseUrl: string
  readonly token: string

  constructor(baseUrl: string, token: string) {
    this.baseUrl = baseUrl
    this.token = token
  }

  private async once(command: string, body: string, t: Timeouts): Promise<Object | null> {
    const req = http.createHttp()
    try {
      const res = await req.request(`${this.baseUrl}/api/${command}`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${this.token}`,
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: t.connect,
        readTimeout: t.read,
        usingCache: false,
        // Default cap is 5 MB; long conversations are several times that.
        maxLimit: 100 * 1024 * 1024
      })
      const text = typeof res.result === 'string' ? res.result as string : ''
      if (res.responseCode < 200 || res.responseCode >= 300) {
        throw ApiError.fromResponse(res.responseCode, text)
      }
      return parseJson(text)
    } catch (e) {
      if (e instanceof ApiError) {
        throw e as ApiError
      }
      const err = e as Error
      throw new ApiError(0, 'network', err.message ?? String(e))
    } finally {
      req.destroy()
    }
  }

  /** Sends a command; transport failures and 5xx are retried once after 400 ms. */
  async call(command: string, body?: JObj, t: Timeouts = Timeouts.DEFAULT): Promise<Object | null> {
    const payload = JSON.stringify(body ?? ({} as JObj))
    try {
      return await this.once(command, payload, t)
    } catch (e) {
      const ae = e as ApiError
      if (!ae.isTransient) {
        throw ae
      }
      await sleep(400)
      return await this.once(command, payload, t)
    }
  }

  /** For mutations whose result is irrelevant; never retried. */
  async send(command: string, body?: JObj, t: Timeouts = Timeouts.DEFAULT): Promise<Object | null> {
    return await this.once(command, JSON.stringify(body ?? ({} as JObj)), t)
  }

  async upload(file: UploadFile, sessionId?: string): Promise<Object | null> {
    const req = http.createHttp()
    try {
      const parts: http.MultiFormData[] = []
      if (sessionId !== undefined) {
        parts.push({ name: 'session_id', contentType: 'text/plain', data: sessionId })
      }
      parts.push({
        name: 'file', contentType: file.mimeType, remoteFileName: file.name, filePath: file.filePath
      })
      const res = await req.request(`${this.baseUrl}/api/upload_attachment`, {
        method: http.RequestMethod.POST,
        header: { 'Authorization': `Bearer ${this.token}`, 'Content-Type': 'multipart/form-data' },
        multiFormDataList: parts,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 30000,
        readTimeout: 300000
      })
      const text = typeof res.result === 'string' ? res.result as string : ''
      if (res.responseCode === 413) {
        throw new ApiError(413, 'too_large', 'File exceeds the server upload limit')
      }
      if (res.responseCode < 200 || res.responseCode >= 300) {
        throw ApiError.fromResponse(res.responseCode, text)
      }
      return parseJson(text)
    } finally {
      req.destroy()
    }
  }

  get wsUrl(): string {
    const m = new RegExp('^(https?)://([^/]+)').exec(this.baseUrl)
    if (m === null) {
      return ''
    }
    return `${m[1] === 'https' ? 'wss' : 'ws'}://${m[2]}/ws/events`
  }

  /** Token for the WebSocket subprotocol: base64url without padding. */
  get wsProtocol(): string {
    const b64 = base64Encode(this.token)
    const url = b64.replace(new RegExp('\\+', 'g'), '-').replace(new RegExp('/', 'g'), '_')
      .replace(new RegExp('=+$'), '')
    return `codeg-events, codeg-token.${url}`
  }

  videoUrl(token: string): string {
    return `${this.baseUrl}/api/video-preview/${token}`
  }
}

function base64Encode(s: string): string {
  const bytes = new util.TextEncoder().encodeInto(s)
  return new util.Base64Helper().encodeToStringSync(bytes)
}
