#!/usr/bin/env bash
# Build the openGym mobile bundle and drop it where the Swift shell expects it.
#
#   ios-shell/Sources/openGym/WebBundle/
#
# Three flags, and each one matters:
#
#   VITE_MOBILE=1       the phone flavour. Without it the bundle is the self-hosted web app:
#                       sign-in, passkeys, a service worker, a server. The marker
#                       <meta name="opengym-flavor" content="mobile"> is how
#                       scripts/check-mobile-bundle.mjs proves which one landed.
#
#   VITE_NATIVE_SHIM=1  points every @capacitor/* dynamic import at src/native/. Those imports
#                       are all MOBILE-gated, so this only affects a phone bundle.
#
# No `cap sync`, unlike upstream's build:mobile. Capacitor is not a dependency of this shell —
# it ships only podspecs, which SwiftPM cannot read — so there are no native projects to sync.
#
# Media: stills by default (46 MB, 6554 files). MEDIA=clips adds the 170 MB of MP4 animations.
# The app works either way; lib/catalogue.js falls back to a still when a clip is missing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$HERE/upstream"
FRONTEND="$HERE/frontend"
OUT="$HERE/ios-shell/Sources/openGym/WebBundle"

cd "$FRONTEND"

# APP_NAME is empty by default, which leaves openGym's own name in the header, the document
# title and the home-screen label. Set it to ship the app under a different one.
APP_NAME="${APP_NAME:-}"

echo "==> vite build (mobile + native shim${APP_NAME:+, as "$APP_NAME"})"
APP_NAME="$APP_NAME" VITE_MOBILE=1 VITE_NATIVE_SHIM=1 npx vite build

echo "==> staging media (${MEDIA:-stills})"
node "$UPSTREAM/scripts/catalogue/stage-media.mjs" dist
if [ "${MEDIA:-stills}" = "clips" ]; then
  echo "    (clips already staged by the step above)"
else
  echo "==> dropping MP4 clips to keep the bundle small"
  rm -rf dist/exercise-media/clip
fi

echo "==> verifying the phone flavour landed"
node -e '
  const { readFileSync } = require("node:fs")
  const html = readFileSync("dist/index.html", "utf8")
  if (!/<meta\s+name="opengym-flavor"\s+content="mobile"/.test(html)) {
    console.error("dist/index.html is the web build, not the mobile build")
    process.exit(1)
  }
  for (const [, ref] of html.matchAll(/(?:src|href)="\.?\/?(assets\/[^"]+\.(?:js|css))"/g)) {
    if (!require("node:fs").existsSync("dist/" + ref)) {
      console.error("index.html loads " + ref + ", which is missing")
      process.exit(1)
    }
  }
  console.log("    mobile build confirmed, all chunk references resolve")
'

echo "==> installing into $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -r dist/. "$OUT/"

echo
echo "Bundle size:"
du -sh "$OUT"
echo "Files: $(find "$OUT" -type f | wc -l)"
echo
echo "Next: cd ios-shell && xtool dev build"