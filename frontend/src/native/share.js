// Share and SecureStorage.
//
// Share exists because WKWebView cannot download a blob URL: a backup export goes to a temp file
// in Caches/ and out through the OS share sheet (Files, AirDrop, mail).
//
// SecureStorage holds two things and nothing else: the Coach's provider API key and the
// Cloudflare Access service token. lib/coach-secrets.js is explicit that these must never reach
// the synced state S, never touch localStorage, and never appear in an export — which is why they
// go to the Keychain and not to a file. The process-local fallback there stays in force whenever
// the plugin is missing or slow, so a failed keychain read degrades to a forgetful map rather than
// an exception.
import { call } from './bridge.js'

export const Share = {
  async share({ title, text, url } = {}) {
    const r = await call('Share', 'share', { title, text, url })
    return { activityType: r.activityType || null }
  },
}

// Unlike the Capacitor plugins above, this one is called positionally — lib/coach-secrets.js does
// `p.get(key)` and `p.set(key, v)` — so the first argument is the key, not an options object.
// Both forms are accepted because the object form costs one line and removes a class of silent
// breakage if upstream ever aligns with the other plugins.
const keyOf = (a, b) => (typeof a === 'string' ? a : a?.key)
const valueOf = (a, b) => (typeof a === 'string' ? b : a?.value)

export const SecureStorage = {
  async get(a, b) {
    const r = await call('SecureStorage', 'get', { key: keyOf(a, b) })
    return r.value ?? null
  },
  async set(a, b) {
    await call('SecureStorage', 'set', { key: keyOf(a, b), value: valueOf(a, b) })
  },
  async remove(a, b) {
    await call('SecureStorage', 'remove', { key: keyOf(a, b) })
  },
}

// Print is a local plugin in upstream (android MainActivity / ios PrintPlugin.m) registered by
// name, not imported. Exported here under the same name so the registerPlugin lookup in
// lib/mobile.js printHtml() finds it, and so the import path is available to a test.
export const Print = {
  printHtml: ({ html, name } = {}) => call('Print', 'printHtml', { html, name }),
}