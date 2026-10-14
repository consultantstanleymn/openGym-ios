#!/usr/bin/env bash
# Screenshot the phone bundle at iPhone viewport.
#
# Chrome runs in a flatpak sandbox and cannot see /tmp/opencode, so every output lands under
# ~/.var/app/com.google.Chrome/design — that path is bind-mounted from the host.
#
#   scripts/shoot.sh <name> [width] [height] [extra-query]
#
# The bundle on :8099 is the VITE_MOBILE=1 build — the same one the app ships — so what is
# captured here is what the phone draws, minus the native bridge, which the shims fall back
# from cleanly. Good enough to judge layout, type and colour; not a substitute for the device
# for anything touching the Keychain or a notification.
set -euo pipefail

NAME="${1:-shot}"
W="${2:-393}"
H="${3:-852}"
QUERY="${4:-}"
PORT="${PORT:-8099}"
OUT="$HOME/.var/app/com.google.Chrome/design"
CHROME=/var/lib/flatpak/exports/bin/com.google.Chrome

mkdir -p "$OUT"
URL="http://localhost:${PORT}/"
[ -n "$QUERY" ] && URL="${URL}?${QUERY}"

"$CHROME" \
  --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
  --user-data-dir="$OUT/prof" \
  --window-size="${W},${H}" \
  --force-device-scale-factor=2 \
  --virtual-time-budget=12000 \
  --screenshot="$OUT/${NAME}.png" \
  "$URL" 2>/dev/null | tail -1 || true

if [ -f "$OUT/${NAME}.png" ]; then
  echo "$OUT/${NAME}.png"
else
  echo "FAILED: no screenshot at $OUT/${NAME}.png" >&2
  exit 1
fi