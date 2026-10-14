// @capacitor-mlkit/barcode-scanning, reimplemented in JavaScript.
//
// Upstream decodes gym check-in codes with ML Kit, whose native scanner is Google's: an Android
// Play Services dependency and, on iOS, Firebase ML Kit. Neither is reachable from a SwiftPM
// package without dragging a binary distribution into the build, and xtool cannot compile the
// plugin's own native sources either.
//
// What replaces it is already in the project. lib/scan-web.js decodes a QR with jsQR
// (Apache-2.0, NOTICE.md) on a canvas — it is what the browser PWA uses, and it was written to
// work on iOS Safari, which has no BarcodeDetector. So the two halves of this shim are:
//
//   readBarcodesFromImage  fully implemented. The file is read back through the Filesystem shim
//                         as base64, decoded, and the temp file the caller wrote is untouched.
//                         Photo import of a check-in code therefore works exactly as upstream.
//
//   scan()                 not implemented. This is the live camera scanner, and ML Kit supplies
//                         its own full-screen UI on Android rather than a camera view the host
//                         app owns — there is no equivalent to hand back here, and building one
//                         means a camera permission flow, a preview layer and a session object.
//                         It rejects with a specific error, which is what lib/scan.js turns into
//                         "not supported on this build", so the view falls back to photo import
//                         and manual entry instead of failing silently.
//
// The camera permission calls are answered as granted because the image path needs no camera:
// returning denied would send scan.js down a permission-denied branch for a flow that never opens
// one.
import { Filesystem, Directory } from './filesystem.js'

const NO_SCANNER = 'the live camera scanner is not available in this build; import a photo instead'

function dirOf(uri) {
  // The caller writes the temp file to CACHE and hands back a file:// uri; strip the scheme so
  // the name can be re-read through the same directory it came from.
  const name = String(uri || '').replace(/^file:\/\//, '')
  return name ? { path: name, directory: Directory.Cache } : null
}

export const BarcodeScanner = {
  async isSupported() {
    // True for the image path, which is the one that works. scan() makes its own refusal.
    return { supported: true }
  },

  async checkPermissions() {
    return { camera: 'granted' }
  },

  async requestPermissions() {
    return { camera: 'granted' }
  },

  async isGoogleBarcodeScannerModuleAvailable() {
    // Android-only concept. Reporting available makes lib/scan.js's ensureScannerModule() a
    // no-op here, which is the same outcome it reaches on iOS upstream.
    return { available: true }
  },

  async scan() {
    throw new Error(NO_SCANNER)
  },

  async readBarcodesFromImage({ path } = {}) {
    const ref = dirOf(path)
    if (!ref) throw new Error('readBarcodesFromImage needs a path')
    const { data } = await Filesystem.readFile({ ...ref, encoding: 'base64' })
    const { value } = await decodeBase64(data)
    if (!value) return { barcodes: [] }
    // The shape lib/scan.js reads: rawValue plus a format, which qr.js normalises.
    return { barcodes: [{ rawValue: value, displayValue: value, format: 'QR_CODE' }] }
  },
}

// base64 → ImageData → jsQR, reusing the browser decoder the PWA already ships.
async function decodeBase64(base64) {
  const mime = sniffImageType(base64)
  const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0))
  const blob = new Blob([bytes], { type: mime })
  const url = URL.createObjectURL(blob)
  try {
    const img = new Image()
    img.decoding = 'async'
    await new Promise((resolve, reject) => {
      img.onload = resolve
      img.onerror = () => reject(new Error('could not decode the image'))
      img.src = url
    })
    const { decodeSource } = await import('../lib/scan-web.js')
    return (await decodeSource(img)) || { value: null }
  } finally {
    URL.revokeObjectURL(url)
  }
}

// Magic bytes, so a photo with no extension still loads as the type it is.
function sniffImageType(base64) {
  if (base64.startsWith('/9j/')) return 'image/jpeg'
  if (base64.startsWith('iVBORw0KGgo')) return 'image/png'
  if (base64.startsWith('R0lGOD')) return 'image/gif'
  if (base64.startsWith('UklGR')) return 'image/webp'
  return 'image/jpeg'
}

export default { BarcodeScanner }