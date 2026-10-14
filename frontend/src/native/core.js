// The pieces of @capacitor/core the app uses: getPlatform, isNativePlatform, convertFileSrc and
// registerPlugin.
import { call, available } from './bridge.js'

// openGym branches on the platform string in exactly two places: isAndroid() in lib/mobile.js
// (the APK updater, the RestAlert alarm and the SystemBars plugin all sit behind it) and the
// barcode scanner in lib/scan.js. 'ios' is the honest answer here; everything Android-only then
// takes its existing early return and never reaches the bridge.
export const Capacitor = {
  getPlatform: () => 'ios',
  isNativePlatform: () => available(),
  getName: () => 'openGym',
  getVersion: () => '1.0.0',
  // The Capacitor original rewrites capacitor:// file URLs for a <img> to read. This shell serves
  // everything from the app:// scheme already, so a URI is passed through untouched.
  convertFileSrc: (path) => path,
}

// registerPlugin hands out a proxy that forwards every property to a native method.
//
// `then` is the trap worth naming. A Capacitor plugin proxy answers *every* property name with a
// native-method wrapper, then included, so a promise that resolves to the bare proxy is treated
// as a thenable: JavaScript calls `then(resolve, reject)`, the native side reports "not
// implemented", and nothing ever settles. openGym hit that as a real hang — issues #42 and #58,
// the Coach's "Save and use the Coach" button greyed out forever (lib/coach-secrets.js).
//
// So `then` invokes the rejection callback it is handed. That makes `await plugin` reject
// promptly, which is the whole point: a mistaken await now fails loudly at that line instead of
// hanging the UI, and no unhandled rejection is left behind.
//
// Also note the upstream call sites never await the bare proxy — they wrap it in an object
// ({ Print }) first. This shim keeps that working either way.
export function registerPlugin(name) {
  return new Proxy(
    {},
    {
      get(_target, prop) {
        if (typeof prop !== 'string') return undefined
        if (prop === 'then') {
          return (_resolve, reject) => {
            reject(new Error(`${name}.then is not implemented`))
          }
        }
        return (...args) => call(name, prop, args[0] ?? {})
      },
    }
  )
}

export default { Capacitor, registerPlugin }