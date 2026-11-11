import { randomUUID } from 'node:crypto'
export const util = {
  generateRandomUUID(_: boolean): string { return randomUUID() },
  TextEncoder: class { encodeInto(s: string): Uint8Array { return new TextEncoder().encode(s) } },
  Base64Helper: class { encodeToStringSync(b: Uint8Array): string { return Buffer.from(b).toString('base64') } }
}
