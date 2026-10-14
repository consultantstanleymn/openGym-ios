# openGym for iOS, built from Linux

openGym is a self-hosted gym and bodyweight tracker by [Duarte Santos](https://github.com/DuarteSantos8/openGym),
licensed AGPL-3.0-or-later. Its own iOS app is a Capacitor project, and Capacitor cannot be built
on Linux — it ships CocoaPods podspecs, no Swift Package Manager manifest, and its Xcode target
uses a storyboard and an asset catalog.

**This builds it anyway.** The app here is a hand-written SwiftPM shell around openGym's own web
bundle, compiled and packaged entirely on this Fedora machine with
[xtool](https://github.com/xtool-org/xtool). No Mac was involved at any point.

The result is `ios-shell/xtool/openGym.ipa` — 61 MB, arm64, iOS 17.4+.

## How it works

```
frontend/src/native/        JavaScript stand-ins for the Capacitor plugins
        │  one WKScriptMessageHandler named "ogNative"
        ▼
ios-shell/Sources/openGym/  SwiftPM shell: WKWebView, scheme handler, the plugins themselves
        │  serves the bundle over app://
        ▼
WebBundle/                  openGym's mobile build, VITE_MOBILE=1, with 6554 exercise stills
```

### Why a reimplementation rather than Capacitor

Every `@capacitor/*` import in openGym's `frontend/src` is a **dynamic import guarded by `MOBILE`**,
so none of it reaches a web bundle. The surface actually used is small and was measured, not
guessed:

| Shim | Methods | Why it is needed |
|---|---|---|
| `core` | `getPlatform`, `isNativePlatform`, `convertFileSrc`, `registerPlugin` | platform checks and the `Print` lookup |
| `filesystem` | `readFile`, `writeFile`, `appendFile`, `deleteFile`, `deleteDirectory`, `readdir`, `mkdir`, `rmdir`, `getUri`, `stat`, `exists` | the `opengym-state.json` mirror, auto-backups, media, share-sheet exports |
| `local-notifications` | `checkPermissions`, `requestPermissions`, `schedule`, `cancel`, `getPending` | the 60-day workout reminder and the 7-day missed-workout nudge |
| `app` | `addListener`, `exitApp`, `getInfo` | `appStateChange`, so the reminder window rebuilds on foreground |
| `share` | `share` | WKWebView cannot download a blob URL |
| `secure-storage` | `get`, `set`, `remove` | the Coach API key and the Cloudflare Access token, in the Keychain |
| `Print` | `printHtml` | the weekly plan through the iOS print sheet |

`VITE_NATIVE_SHIM=1` points those specifiers at `src/native/`. openGym's own application code is
unmodified: `lib/mobile.js` still says `await import('@capacitor/filesystem')` and still gets a
`Filesystem` with the shape it expects. There is no fork of the app to keep in step — only this
directory, with 25 unit tests over it.

### Four Capacitor plugins are deliberately absent

`RestAlert`, `SystemBars`, `Install`, `BackupFolder` and `HealthConnect` are Android-only and all
sit behind `if (!(await isAndroid())) return null` in openGym's own code. On iOS the registerPlugin
proxy rejects them, which is the branch upstream already takes. The notable one is `RestAlert`: a
foreground service that keeps the rest countdown sounding with the screen locked. iOS has no
equivalent, and `lib/rest-alert.js` already falls back to a scheduled notification there.

The live camera QR scanner (`BarcodeScanner.scan`) is likewise unimplemented — ML Kit supplies its
own full-screen UI, which is not something to rebuild. Photo import of a check-in code works: the
shim decodes with jsQR, reusing `lib/scan-web.js`, the decoder the browser PWA already ships.

### Why `app://` and not `file://`

A WKWebView loaded from `file://` runs in an opaque origin, which gets no localStorage at all. openGym
keeps its entire state there. `AppSchemeHandler` serves the bundle over a custom scheme so the page
has a real, persistent origin. This is the load-bearing decision in the shell.

## Building

Prerequisites, all installed here:

- Swift 6.4.1 (`~/.local/swift`, the swift.org Fedora 41 build)
- xtool 1.22.2 (`/usr/local/bin/xtool`)
- Node 20+ and npm
- A Darwin Swift SDK — `xtool sdk install ~/Downloads/Xcode.xip --slim`, built from Xcode 27
  against `iPhoneOS27.0.sdk`

```sh
# 1. the web bundle (VITE_MOBILE=1 + the native shim, then staged into the app)
bash scripts/build-web.sh

# 2. the app
cd ios-shell
xtool dev build                          # -> xtool/openGym.app
xtool dev build --configuration release --ipa   # -> xtool/openGym.ipa
```

`upstream/` is a shallow clone of openGym at a pinned commit. It supplies `frontend/`'s origin, the
`api/coach` core the bundle imports, and `catalogue/media`. It is never committed.

To install:

```sh
xtool auth login     # Apple ID; a free one works, with 7-day signatures
xtool devices        # the iPhone must be visible over USB
xtool dev run        # build, install and launch
```

## Licence and scope

**This is a personal build, not published anywhere.** There is deliberately no git remote
configured on this repository. Nothing here goes to GitHub, to GitHub Pages, or to a portfolio
without a separate conversation about what can be redistributed.

- **openGym's code** is AGPL-3.0-or-later, © Duarte Santos, and this derivative keeps that licence.
  See `NOTICE.upstream` for their third-party notices, including the app-store exception under
  AGPL §7 and the MuscleMap body-diagram attribution.
- **The exercise media** (`catalogue/media/`, 13,109 files) is © Aliaksandr Makatserchyk, Gym
  visual. It is licensed for use within openGym and is explicitly *not* AGPL. Upstream's notice is
  unambiguous: third parties have no rights to reuse, extract or integrate it into independent
  apps, websites or products. It is gitignored here, fetched by cloning `upstream/`, and staged
  into a local build only.
- **This shell** — `ios-shell/`, `frontend/src/native/`, `scripts/` — is the work of
  Stanley Sujith Nelavala.

The consequence, stated plainly: this build is fine to run on your own phone and is not fine to
publish, because publishing the bundle would redistribute media that is not ours to give away. The
six thousand exercise animations are the reason that matters, and they are also the app's main
visual feature — so this is a real constraint on any future public version, not a technicality.

## Tests

```sh
cd frontend && npm test          # openGym's own suite
npx vitest run src/native/       # the shim's 25 tests
```

The upstream suite is 5059 passing against one pre-existing failure in
`src/sheets.day-note.test.jsx`, which is upstream's and unrelated to anything here.

## Credits

- [openGym](https://github.com/DuarteSantos8/openGym) — Duarte Santos. Everything in `frontend/`,
  `api/` and the design.
- [xtool](https://github.com/xtool-org/xtool) — the cross-platform Xcode replacement that makes a
  Linux-built iOS app possible.
- [jsQR](https://github.com/cozmo/jsQR) — Apache-2.0, the fallback QR decoder.