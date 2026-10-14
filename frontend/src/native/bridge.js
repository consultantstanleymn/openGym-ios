// The one channel between the openGym web bundle and the Swift shell.
//
// Capacitor is not used here. It ships only CocoaPods podspecs, so SwiftPM (and therefore xtool)
// cannot consume it, and the plugin surface this app actually touches is small enough to
// reimplement — see ./index.js for the list. This module is that reimplementation's transport.
//
// The Swift side registers a WKScriptMessageHandlerWithReply named HANDLER. That API has existed
// since iOS 14 and returns a promise on the JavaScript side, so a call is a straight await: a
// thrown Swift error arrives here as a rejection, with no id bookkeeping and no timeout to leak.
//
// Values crossing the boundary are JSON. A Date therefore becomes an ISO string, so the two
// places that pass one — a notification's schedule.at — are converted here, once, instead of at
// every call site.

export const HANDLER = 'ogNative'

// Callers sit behind try/catch almost everywhere, but not everywhere: a missing bridge must not
// surface as a TypeError from deep inside a store update. Every call rejects instead.
export function available() {
  return typeof window !== 'undefined' && !!window.webkit?.messageHandlers?.[HANDLER]
}

const DATE = '@date'

// JSON has no Date. Mark them so the native side can read the millisecond value back.
//
// An undefined value is dropped rather than marked. JSON.stringify does the same, and for this
// boundary the two are indistinguishable: a Swift argument decoded from an absent key and one
// decoded from an explicit null both arrive as nil. Keeping them distinct would mean every
// optional argument — Share.text, a notification's allowWhileIdle — crosses as a sentinel object
// the native side then has to unwrap.
export function encode(value) {
  if (value instanceof Date) return { [DATE]: value.getTime() }
  if (value === undefined) return undefined
  if (Array.isArray(value)) return value.map(encode)
  if (value && typeof value === 'object') {
    const out = {}
    for (const k of Object.keys(value)) {
      const v = encode(value[k])
      if (v !== undefined) out[k] = v
    }
    return out
  }
  return value
}

export function call(plugin, method, args) {
  if (!available()) {
    return Promise.reject(new Error(`native bridge unavailable (${plugin}.${method})`))
  }
  return window.webkit.messageHandlers[HANDLER].postMessage({
    plugin,
    method,
    args: encode(args ?? {}),
  })
}

// MARK: - events
//
// The other direction. The shell registers `ogEvents` as a plain WKScriptMessageHandler and calls
// it with a JSON string whenever the app changes state; that lands in EventSink in AppDelegate.swift,
// which evaluates window.ogNativeDispatch(json) back in the page.
//
// Only appStateChange is used — lib/mobile.js initReminderSync and onAppActive both want to know
// when the phone came back to the foreground. No closure crosses the boundary in either
// direction: addListener registers here by event name, and native pushes a name plus a payload.

const eventListeners = new Map()   // event -> Set<handler>

/**
 * Subscribe to a native event.
 * @param {string} event
 * @param {(payload: any) => void} handler
 * @returns {() => void} unsubscribe
 */
export function on(event, handler) {
  if (!eventListeners.has(event)) eventListeners.set(event, new Set())
  eventListeners.get(event).add(handler)
  return () => eventListeners.get(event)?.delete(handler)
}

/** Deliver a pushed event. Installed by the shell; a no-op in a browser. */
export function installEventDispatch() {
  if (typeof window === 'undefined') return
  window.ogNativeDispatch = raw => {
    let body
    try {
      body = JSON.parse(raw)
    } catch {
      return
    }
    for (const handler of eventListeners.get(body?.event) ?? []) {
      try {
        handler(body.payload)
      } catch {
        // One bad listener must not stop the others.
      }
    }
  }
}

installEventDispatch()
// MARK: - console
//
// Forwards the page's console to the `ogConsole` script handler, which prints into the device
// log (AppDelegate.swift). With no Developer Disk Image mounted there is no screenshot and no
// Web Inspector, so this is the only way to see a JavaScript exception during boot instead of
// staring at a blank screen. Warnings and errors only: the app is chatty and the log is not.
if (typeof window !== 'undefined') {
  const sink = window.webkit?.messageHandlers?.ogConsole
  if (sink) {
    for (const level of ['warn', 'error']) {
      const original = console[level]
      console[level] = (...args) => {
        try {
          sink.postMessage({
            level,
            text: args
              .map(a => (a instanceof Error ? a.message
                : typeof a === 'object' ? JSON.stringify(a)
                  : String(a)))
              .join(' '),
          })
        } catch { /* never let logging break the app */ }
        original.apply(console, args)
      }
    }
  }
}
