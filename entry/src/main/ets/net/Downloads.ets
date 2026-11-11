import { http } from '@kit.NetworkKit'
import { fileIo as fs } from '@kit.CoreFileKit'
import { CodegClient } from './CodegClient'
import { ApiError } from './ApiError'
import { asObj, num } from '../common/Json'

/** Folder for files fetched to be saved or handed to another app; created on first use. */
export function downloadsDir(cacheDir: string): string {
  const dir = `${cacheDir}/downloads`
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir)
  }
  return dir
}

/** Removes downloads older than a day, so fetched videos do not pile up in the cache. */
export function pruneDownloads(dir: string): void {
  try {
    const cutoff = Date.now() / 1000 - 86400
    for (const name of fs.listFileSync(dir)) {
      const p = `${dir}/${name}`
      if (fs.statSync(p).mtime < cutoff) {
        fs.unlinkSync(p)
      }
    }
  } catch (e) {
    // Best effort.
  }
}

/**
 * Copies a local file into one the user picked (a path or a picker URI), in
 * chunks, pausing between them so a large copy does not freeze the UI.
 */
export async function copyFileInto(srcPath: string, dest: string): Promise<void> {
  const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY)
  try {
    // The save picker has already created `dest`; it may be an existing file the user chose to replace.
    const dst = fs.openSync(dest, fs.OpenMode.READ_WRITE)
    try {
      try {
        fs.truncateSync(dst.fd, 0)
      } catch (e) {
        // Not supported for this destination; a new file is empty anyway.
      }
      const buf = new ArrayBuffer(1024 * 1024)
      let chunks = 0
      let n = fs.readSync(src.fd, buf)
      while (n > 0) {
        fs.writeSync(dst.fd, n === buf.byteLength ? buf : buf.slice(0, n))
        chunks++
        if (chunks % 16 === 0) {
          await new Promise<void>((resolve: () => void) => {
            setTimeout(resolve, 0)
          })
        }
        n = fs.readSync(src.fd, buf)
      }
    } finally {
      fs.closeSync(dst)
    }
  } finally {
    fs.closeSync(src)
  }
}

function removeQuietly(path: string): void {
  try {
    fs.unlinkSync(path)
  } catch (e) {
    // Never created, or already gone.
  }
}

/**
 * Streams a file from the server's workspace into `destPath` without holding
 * it in memory, so videos and archives of any size work. Returns the number of
 * bytes written. On any failure `destPath` is removed and an ApiError thrown.
 * `onProgress(received, total)`: `total` is 0 when the server does not say.
 */
export async function downloadWorkspaceFile(c: CodegClient, rootPath: string, relPath: string, destPath: string,
  onProgress: (received: number, total: number) => void): Promise<number> {
  const file = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY)
  const req = http.createHttp()
  let received = 0
  let total = 0
  let writeFailure = ''
  let ended = false
  req.on('headersReceive', (h: Object) => {
    const o = asObj(h)
    total = num(o, 'content-length', num(o, 'Content-Length'))
  })
  req.on('dataReceive', (data: ArrayBuffer) => {
    if (writeFailure.length > 0) {
      return
    }
    try {
      fs.writeSync(file.fd, data)
      received += data.byteLength
      onProgress(received, total)
    } catch (e) {
      writeFailure = (e as Error).message ?? 'write failed'
    }
  })
  req.on('dataEnd', () => {
    ended = true
  })
  let code = 0
  let failure = ''
  try {
    code = await req.requestInStream(`${c.baseUrl}/api/download_workspace_file`, {
      method: http.RequestMethod.POST,
      header: {
        'Authorization': `Bearer ${c.token}`,
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify({ 'rootPath': rootPath, 'path': relPath }),
      connectTimeout: 30000,
      // Covers the whole transfer, not just a pause in it.
      readTimeout: 3600000,
      maxLimit: 100 * 1024 * 1024,
      usingCache: false
    })
    // The status can arrive before the last chunks are delivered: wait for the
    // end of the stream, giving up only once nothing has arrived for 5 s.
    let seen = received
    let idleMs = 0
    while (!ended && idleMs < 5000) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 100)
      })
      idleMs = received === seen ? idleMs + 100 : 0
      seen = received
    }
  } catch (e) {
    failure = (e as Error).message ?? String(e)
  } finally {
    req.off('headersReceive')
    req.off('dataReceive')
    req.off('dataEnd')
    req.destroy()
    fs.closeSync(file)
  }
  if (failure.length > 0) {
    removeQuietly(destPath)
    throw new ApiError(0, 'network', failure)
  }
  if (code < 200 || code >= 300) {
    // The body that was written is the server's JSON error.
    let body = ''
    try {
      body = fs.readTextSync(destPath)
    } catch (e) {
      body = ''
    }
    removeQuietly(destPath)
    throw ApiError.fromResponse(code, body.substring(0, 2000))
  }
  if (writeFailure.length > 0) {
    removeQuietly(destPath)
    throw new ApiError(0, 'storage', writeFailure)
  }
  if (total > 0 && received !== total) {
    removeQuietly(destPath)
    throw new ApiError(0, 'network', `incomplete download: ${received} of ${total} bytes`)
  }
  return received
}
