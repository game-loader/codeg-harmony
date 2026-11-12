// Node stand-in for @kit.CoreFileKit: the parts of fileIo the download code uses.
// OpenMode values equal Linux open(2) flags, so they pass straight through.
import * as nfs from 'node:fs'

export const fileIo = {
  OpenMode: { READ_ONLY: 0o0, WRITE_ONLY: 0o1, READ_WRITE: 0o2, CREATE: 0o100, TRUNC: 0o1000 },
  openSync(path: string, mode: number = 0): { fd: number } { return { fd: nfs.openSync(path, mode) } },
  closeSync(f: number | { fd: number }): void { nfs.closeSync(typeof f === 'number' ? f : f.fd) },
  writeSync(fd: number, data: ArrayBuffer | string): number {
    return typeof data === 'string' ? nfs.writeSync(fd, data) : nfs.writeSync(fd, new Uint8Array(data))
  },
  readSync(fd: number, buf: ArrayBuffer): number { return nfs.readSync(fd, new Uint8Array(buf)) },
  truncateSync(fd: number, len: number = 0): void { nfs.ftruncateSync(fd, len) },
  unlinkSync(path: string): void { nfs.unlinkSync(path) },
  accessSync(path: string): boolean { return nfs.existsSync(path) },
  mkdirSync(path: string): void { nfs.mkdirSync(path, { recursive: true }) },
  listFileSync(path: string): string[] { return nfs.readdirSync(path) },
  statSync(path: string): { size: number, mtime: number, isDirectory(): boolean } {
    const s = nfs.statSync(path)
    return { size: s.size, mtime: Math.floor(s.mtimeMs / 1000), isDirectory: () => s.isDirectory() }
  },
  rmdirSync(path: string): void { nfs.rmdirSync(path) },
  readTextSync(path: string): string { return nfs.readFileSync(path, 'utf8') }
}
export const fileUri = { getUriFromPath(p: string): string { return `file://test${p}` } }
export const picker: any = {}
