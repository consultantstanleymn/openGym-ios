import { describe, it, expect, beforeEach, vi } from 'vitest'
import { HANDLER, encode, available, on, installEventDispatch } from './bridge.js'
import { Filesystem, Directory, Encoding } from './filesystem.js'
import { LocalNotifications, App } from './plugins.js'
import { Share, SecureStorage } from './share.js'
import { Capacitor, registerPlugin } from './core.js'

// The shell answers through WKScriptMessageHandlerWithReply, which is a promise on the JS side.
// So a fake handler is just a function returning a resolved value, and an assertion about what
// crossed the boundary is a look at the payload it was handed.
//
// installEventDispatch() runs once at module load in the real app, where window already exists.
// These tests swap window afterwards, so it is re-installed here — the same thing the shell gets
// when it evaluates window.ogNativeDispatch.
function installBridge(impl = () => ({})) {
  const calls = []
  const handler = vi.fn(async payload => {
    calls.push(payload)
    return impl(payload)
  })
  globalThis.window = { webkit: { messageHandlers: { [HANDLER]: { postMessage: handler } } } }
  installEventDispatch()
  return { handler, calls }
}

function removeBridge() {
  delete globalThis.window
}

beforeEach(() => {
  vi.restoreAllMocks()
})

describe('bridge', () => {
  it('reports availability from the webkit handler', () => {
    removeBridge()
    expect(available()).toBe(false)
    installBridge()
    expect(available()).toBe(true)
    removeBridge()
  })

  it('rejects rather than throwing when the shell is absent', async () => {
    removeBridge()
    await expect(Filesystem.readFile({ path: 'x' })).rejects.toThrow(/bridge unavailable/)
  })

  it('encodes a Date so schedule.at survives the boundary', () => {
    const at = new Date('2026-03-04T08:00:00.000Z')
    expect(encode({ schedule: { at } })).toEqual({ schedule: { at: { '@date': at.getTime() } } })
  })

  it('encodes undefined as an absent key, as JSON would', () => {
    expect(encode({ a: 1, at: undefined })).toEqual({ a: 1 })
    expect(encode(undefined)).toBeUndefined()
  })

  it('encodes nested arrays and objects', () => {
    const at = new Date(0)
    expect(encode({ notifications: [{ id: 1, schedule: { at } }] }))
      .toEqual({ notifications: [{ id: 1, schedule: { at: { '@date': 0 } } }] })
  })
})

describe('Filesystem', () => {
  it('passes path, directory and encoding through unchanged', async () => {
    const { calls } = installBridge(() => ({ data: 'x', uri: 'app://f' }))
    await Filesystem.readFile({ path: 'opengym-state.json', directory: Directory.Data, encoding: Encoding.UTF8 })
    expect(calls[0].plugin).toBe('Filesystem')
    expect(calls[0].method).toBe('readFile')
    expect(calls[0].args).toEqual({ path: 'opengym-state.json', directory: 'DATA', encoding: 'utf8' })
    removeBridge()
  })

  it('returns the uri a write produced, which shareExport then hands to the share sheet', async () => {
    installBridge(() => ({ uri: 'file:///tmp/openGym-2026-03-04.json' }))
    const w = await Filesystem.writeFile({ path: 'f.json', directory: Directory.Cache, data: '{}', encoding: Encoding.UTF8 })
    expect(w.uri).toBe('file:///tmp/openGym-2026-03-04.json')
    removeBridge()
  })

  it('readdir always returns an array, as the auto-backup pruner assumes', async () => {
    installBridge(() => ({ files: [{ name: 'a.json', type: 'file' }] }))
    expect((await Filesystem.readdir({ path: 'openGym', directory: Directory.Documents })).files).toHaveLength(1)
    removeBridge()
    installBridge(() => ({}))
    expect((await Filesystem.readdir({ path: 'openGym', directory: Directory.Documents })).files).toEqual([])
    removeBridge()
  })

  it('rejects downloadFile and addListener — both belong to the Android APK updater', async () => {
    installBridge()
    await expect(Filesystem.downloadFile({ url: 'u' })).rejects.toThrow(/not implemented/)
    await expect(Filesystem.addListener('progress', () => {})).rejects.toThrow(/not implemented/)
    removeBridge()
  })

  it('appends without a rewrite, so a large blob arrives in pieces', async () => {
    const { calls } = installBridge()
    await Filesystem.appendFile({ path: 'backup.zip', directory: Directory.Cache, data: 'AAA' })
    expect(calls[0].method).toBe('appendFile')
    removeBridge()
  })
})

describe('LocalNotifications', () => {
  it('checks then requests permission, and reports display', async () => {
    installBridge(() => ({ display: 'granted' }))
    expect((await LocalNotifications.checkPermissions()).display).toBe('granted')
    removeBridge()
  })

  it('cancels a window of ids, most of which were never scheduled', async () => {
    const { calls } = installBridge()
    await LocalNotifications.cancel({ notifications: [{ id: 100 }, { id: 1000 }] })
    expect(calls[0].method).toBe('cancel')
    expect(calls[0].args.notifications).toHaveLength(2)
    removeBridge()
  })

  it('schedules with the Date encoded, which is the only Date on the boundary', async () => {
    const { calls } = installBridge()
    const at = new Date('2026-03-04T08:00:00.000Z')
    await LocalNotifications.schedule({ notifications: [{ id: 1000, title: 'Workout day', body: 'Push is on', schedule: { at, allowWhileIdle: true } }] })
    expect(calls[0].args.notifications[0].schedule.at).toEqual({ '@date': at.getTime() })
    removeBridge()
  })
})

describe('App', () => {
  it('addListener resolves a handle that removes itself', async () => {
    installBridge(() => ({ id: 'listener-1' }))
    const h = await App.addListener('appStateChange', () => {})
    expect(h.id).toBe('listener-1')
    expect(typeof h.remove).toBe('function')
    removeBridge()
  })

  it('removing a listener never throws at the call site', async () => {
    installBridge(payload => {
      if (payload.method === 'removeListener') throw new Error('already gone')
      return { id: 'listener-1' }
    })
    const h = await App.addListener('appStateChange', () => {})
    await expect(h.remove()).resolves.toBeUndefined()
    removeBridge()
  })

  it('delivers a pushed appStateChange to the registered listener', async () => {
    installBridge(() => ({ id: 'l1' }))
    const seen = []
    await App.addListener('appStateChange', p => seen.push(p))
    // The shell calls window.ogNativeDispatch with this exact JSON (EventSink, AppDelegate.swift).
    globalThis.window.ogNativeDispatch(JSON.stringify({ event: 'appStateChange', payload: { isActive: true } }))
    expect(seen).toEqual([{ isActive: true }])
    removeBridge()
  })

  it('stops delivering after remove()', async () => {
    installBridge(() => ({ id: 'l1' }))
    const seen = []
    const h = await App.addListener('appStateChange', p => seen.push(p))
    await h.remove()
    globalThis.window.ogNativeDispatch(JSON.stringify({ event: 'appStateChange', payload: { isActive: true } }))
    expect(seen).toEqual([])
    removeBridge()
  })
})

describe('Share', () => {
  it('hands the share sheet a title and the temp file uri', async () => {
    const { calls } = installBridge(() => ({ activityType: 'com.apple.share-services' }))
    await Share.share({ title: 'openGym-2026-03-04.json', url: 'file:///tmp/x.json' })
    expect(calls[0]).toMatchObject({ plugin: 'Share', method: 'share' })
    expect(calls[0].args).toEqual({ title: 'openGym-2026-03-04.json', url: 'file:///tmp/x.json' })
    removeBridge()
  })
})

describe('SecureStorage', () => {
  // coach-secrets.js calls these positionally: p.get(key), p.set(key, value).
  it('accepts the positional call the app actually makes', async () => {
    const { calls } = installBridge(() => ({ value: 'sk-test' }))
    expect(await SecureStorage.get('coach.apiKey')).toBe('sk-test')
    expect(calls[0].args).toEqual({ key: 'coach.apiKey' })
    await SecureStorage.set('coach.apiKey', 'sk-new')
    expect(calls[1].args).toEqual({ key: 'coach.apiKey', value: 'sk-new' })
    removeBridge()
  })

  it('exposes get as a function, which is how coach-secrets.js decides it exists', () => {
    expect(typeof SecureStorage.get).toBe('function')
  })

  it('returns null for a missing key so the caller falls through to its own map', async () => {
    installBridge(() => ({}))
    expect(await SecureStorage.get('coach.apiKey')).toBeNull()
    removeBridge()
  })
})

describe('core', () => {
  it('reports iOS, which is what routes every Android-only feature away', () => {
    expect(Capacitor.getPlatform()).toBe('ios')
  })

  it('registerPlugin forwards to the named native plugin', async () => {
    const { calls } = installBridge()
    const Print = registerPlugin('Print')
    await Print.printHtml({ html: '<h1>plan</h1>', name: 'Weekly plan' })
    expect(calls[0]).toMatchObject({ plugin: 'Print', method: 'printHtml' })
    expect(calls[0].args).toEqual({ html: '<h1>plan</h1>', name: 'Weekly plan' })
    removeBridge()
  })

  // openGym issue #42: a bare plugin proxy resolved into a promise is thenable, and awaiting it
  // hung the Coach screen forever. `then` has to reject.
  it('a bare plugin proxy is not a thenable that can never settle', async () => {
    installBridge()
    const plugin = registerPlugin('RestAlert')
    await expect(Promise.resolve(plugin)).rejects.toThrow(/then is not implemented/)
    removeBridge()
  })

  it('passes a file src through, since the shell serves app:// itself', () => {
    expect(Capacitor.convertFileSrc('app://media/still/0001.webp')).toBe('app://media/still/0001.webp')
  })
})