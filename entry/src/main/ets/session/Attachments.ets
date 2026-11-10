import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { picker, fileIo as fs } from '@kit.CoreFileKit'
import { image } from '@kit.ImageKit'
import { util } from '@kit.ArkTS'
import { common } from '@kit.AbilityKit'
import { PendingImage } from './SessionController'
import { UploadFile } from '../net/CodegClient'

const MAX_EDGE = 2048

function mimeFor(name: string): string {
  const ext = (name.split('.').pop() ?? '').toLowerCase()
  const m: Record<string, string> = {
    'pdf': 'application/pdf', 'txt': 'text/plain', 'md': 'text/markdown', 'json': 'application/json',
    'csv': 'text/csv', 'zip': 'application/zip', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
    'gif': 'image/gif', 'webp': 'image/webp', 'mp4': 'video/mp4', 'mov': 'video/quicktime',
    'html': 'text/html', 'py': 'text/x-python', 'ts': 'text/plain', 'js': 'text/javascript',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  }
  return m[ext] ?? 'application/octet-stream'
}

function nameOf(uri: string): string {
  const raw = uri.split('/').pop() ?? 'file'
  try {
    return decodeURIComponent(raw)
  } catch (e) {
    return raw
  }
}

/** Downscales to MAX_EDGE and re-encodes as JPEG, like the iOS composer does. */
async function encodeImage(uri: string): Promise<PendingImage> {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
  try {
    const src = image.createImageSource(file.fd)
    const info = await src.getImageInfo()
    const w = info.size.width
    const h = info.size.height
    const scale = Math.min(1, MAX_EDGE / Math.max(w, h))
    const pm = await src.createPixelMap({
      desiredSize: { width: Math.round(w * scale), height: Math.round(h * scale) }
    })
    const packer = image.createImagePacker()
    const buf = await packer.packToData(pm, { format: 'image/jpeg', quality: 85 })
    pm.release()
    src.release()
    packer.release()
    const p = new PendingImage()
    p.data = new util.Base64Helper().encodeToStringSync(new Uint8Array(buf))
    p.mimeType = 'image/jpeg'
    p.name = nameOf(uri)
    return p
  } finally {
    fs.closeSync(file)
  }
}

export async function pickImages(max: number): Promise<PendingImage[]> {
  const opts = new photoAccessHelper.PhotoSelectOptions()
  opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
  opts.maxSelectNumber = max
  const res = await new photoAccessHelper.PhotoViewPicker().select(opts)
  const out: PendingImage[] = []
  for (const uri of res.photoUris) {
    out.push(await encodeImage(uri))
  }
  return out
}

/** Picks documents and copies them into the cache dir so the HTTP stack can stream them. */
export async function pickFiles(ctx: common.UIAbilityContext, max: number): Promise<UploadFile[]> {
  const opts = new picker.DocumentSelectOptions()
  opts.maxSelectNumber = max
  const uris = await new picker.DocumentViewPicker(ctx).select(opts)
  const out: UploadFile[] = []
  for (const uri of uris) {
    const name = nameOf(uri)
    const dest = `${ctx.cacheDir}/upload-${Date.now()}-${name}`
    const src = fs.openSync(uri, fs.OpenMode.READ_ONLY)
    try {
      fs.copyFileSync(src.fd, dest)
    } finally {
      fs.closeSync(src)
    }
    const f = new UploadFile()
    f.name = name
    f.mimeType = mimeFor(name)
    f.filePath = dest
    out.push(f)
  }
  return out
}

export function cleanupUpload(f: UploadFile): void {
  try {
    fs.unlinkSync(f.filePath)
  } catch (e) {
    // Already gone.
  }
}

export function agentMention(name: string, agentType: string): string {
  if (!new RegExp('^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').test(agentType)) {
    return ''
  }
  const flat = name.replace(new RegExp('\\s*[\\r\\n]+\\s*', 'g'), ' ')
  const label = flat.length > 0 ? flat : agentType
  const escaped = label.replace(new RegExp('([\\\\`*_~\\[\\]()<>])', 'g'), '\\$1')
  return `[@${escaped}](codeg://agent/${agentType})`
}
