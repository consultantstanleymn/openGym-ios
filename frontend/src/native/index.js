// The complete native surface this shell implements, and the Vite aliases that put it where the
// app's existing dynamic imports look.
//
// Every @capacitor/* import in frontend/src sits behind `MOBILE` and is a dynamic import, so none
// of it reaches a web bundle. Aliasing means the app's own code is untouched: lib/mobile.js still
// says `await import('@capacitor/filesystem')` and still gets a Filesystem with the same shape.
// There is no fork of the app logic to keep in step, only this directory.
//
// What is implemented, and the only reason each is here:
//
//   core              Capacitor.getPlatform/isNativePlatform/convertFileSrc, registerPlugin
//   filesystem        readFile writeFile appendFile deleteFile deleteDirectory readdir mkdir
//                     rmdir getUri stat exists, Directory, Encoding
//   local-notifications  checkPermissions requestPermissions schedule cancel getPending
//   app               addListener (appStateChange), exitApp, getInfo
//   share             share            — WKWebView cannot download a blob URL
//   secure-storage    get set remove    — the Coach key and the CF-Access token
//   Print             printHtml        — the OS print sheet; upstream's own local plugin
//
// Deliberately not implemented, because each is Android-only and sits behind isAndroid():
//
//   RestAlert         a foreground service and an AlarmManager alarm, for the rest countdown to
//                     sound with the screen locked. iOS has neither. lib/rest-alert.js already
//                     resolves this to null there and falls back to the scheduled notification.
//   SystemBars        status-bar icon colour under Android 15's edge-to-edge.
//   Install           the APK updater (lib/update.js downloads an .apk; iOS has no sideload).
//   BackupFolder      an Android system-folder picker.
//   HealthConnect     Android's health store, no iOS equivalent.
//
// Filesystem.downloadFile and Filesystem.addListener are rejected rather than omitted, for the
// same reason: they belong to the APK updater, and a silent undefined would hide a missing
// method instead of reporting one.
export { Capacitor, registerPlugin } from './core.js'
export { Filesystem, Directory, Encoding } from './filesystem.js'
export { LocalNotifications, App } from './plugins.js'
export { Share, SecureStorage, Print } from './share.js'
export { available, HANDLER, encode, call } from './bridge.js'