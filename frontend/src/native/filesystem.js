// Filesystem, Directory and Encoding, in the shape openGym calls them.
//
// Only the methods the app uses are implemented. Anything else throws rather than resolving with
// something empty: a silent undefined here would be a corrupted training log, and a loud one is
// the only signal that a method was added upstream without this shim following it.
//
// Directories are passed to native as their name and resolved there against the app sandbox:
//   Documents  → Documents/            (visible in Files; where the dated auto-backups land)
//   Library    → Library/              (opengym-media/, iOS's backup-exempt folder)
//   Data       → Library/Application Support/   (the opengym-state.json mirror)
//   Cache      → Caches/               (scratch for share-sheet exports)
import { call } from './bridge.js'

export const Directory = {
  Documents: 'DOCUMENTS',
  Library: 'LIBRARY',
  Data: 'DATA',
  Cache: 'CACHE',
  External: 'EXTERNAL',
  ExternalStorage: 'EXTERNAL_STORAGE',
}

export const Encoding = {
  UTF8: 'utf8',
  UTF16: 'utf16',
  ASCII: 'ascii',
  Base64: 'base64',
  DataURL: 'dataUrl',
}

const implemented = new Set([
  'readFile', 'writeFile', 'appendFile', 'deleteFile', 'deleteDirectory',
  'readdir', 'mkdir', 'rmdir', 'getUri', 'stat', 'exists',
])

function unsupported(method) {
  return Promise.reject(new Error(`Filesystem.${method} is not implemented by the native shell`))
}

export const Filesystem = {
  async readFile({ path, directory, encoding } = {}) {
    const r = await call('Filesystem', 'readFile', { path, directory, encoding })
    return { data: r.data, uri: r.uri }
  },
  async writeFile({ path, directory, data, encoding } = {}) {
    const r = await call('Filesystem', 'writeFile', { path, directory, data, encoding })
    return { uri: r.uri }
  },
  async appendFile({ path, directory, data, encoding } = {}) {
    await call('Filesystem', 'appendFile', { path, directory, data, encoding })
  },
  async deleteFile({ path, directory } = {}) {
    await call('Filesystem', 'deleteFile', { path, directory })
  },
  async deleteDirectory({ path, directory, recursive } = {}) {
    await call('Filesystem', 'deleteDirectory', { path, directory, recursive })
  },
  // Capacitor 4+ returns objects carrying a type; openGyn's pruner accepts either, and the
  // native side sends {name, type} so a directory is never mistaken for a stale backup file.
  async readdir({ path, directory } = {}) {
    const r = await call('Filesystem', 'readdir', { path, directory })
    return { files: r.files || [] }
  },
  async mkdir({ path, directory, recursive } = {}) {
    await call('Filesystem', 'mkdir', { path, directory, recursive })
  },
  async rmdir({ path, directory, recursive } = {}) {
    await call('Filesystem', 'rmdir', { path, directory, recursive })
  },
  async getUri({ path, directory } = {}) {
    const r = await call('Filesystem', 'getUri', { path, directory })
    return { uri: r.uri }
  },
  async stat({ path, directory } = {}) {
    return call('Filesystem', 'stat', { path, directory })
  },
  async exists({ path, directory } = {}) {
    return call('Filesystem', 'exists', { path, directory })
  },
  // downloadFile and addListener belong to the in-app APK updater. iOS has no equivalent
  // (lib/update.js gates it on isAndroid), so they reject here by design rather than by omission.
  downloadFile(...a) {
    return unsupported('downloadFile', ...a)
  },
  addListener(...a) {
    return unsupported('addListener', ...a)
  },
}

export { implemented as implementedFilesystemMethods }