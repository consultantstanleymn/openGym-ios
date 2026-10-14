#!/usr/bin/env bash
# Pull screenshots off the iPhone.
#
#   scripts/shots.sh [outdir]
#
# Why not `idevicescreenshot`: it needs a Developer Disk Image mounted on the device, and Xcode 27
# does not ship one — Apple fetches them on demand when a Mac attaches a phone. The whole Xcode.xip
# was decompressed and searched to confirm that (scripts/xip-pull.py is the extractor; 9.06 GB out
# of 1.9 GB, zero occurrences of DeveloperDiskImage.dmg). So the app takes its own picture instead:
# shake the phone, or Settings → About & updates → "Take a screenshot". See
# ios-shell/Sources/openGym/Screenshot.swift.
#
# What lands in Documents/Screenshots is exposed through UIFileSharingEnabled, so ifuse can read it.
# That mount has to be remounted each run: a mount left over from before a write will happily show
# an empty directory, which looks exactly like a feature that is not working.
set -euo pipefail

BUNDLE="XTL-V63Z8847B5.ch.stanley.opengym"     # xtool prefixes the bundle id with the team id
OUT="${1:-$HOME/buddi/screens/iphone}"
MOUNT="$HOME/mnt/sgdocs"

command -v ifuse >/dev/null || { echo "ifuse is not installed: sudo dnf install ifuse" >&2; exit 1; }
lsusb | grep -q "05ac:12a[8b]" || { echo "no iPhone on USB — connect and unlock it" >&2; exit 1; }

mkdir -p "$OUT"

# Always remount. See the note above about a stale mount reading as an empty directory.
fusermount -u "$MOUNT" 2>/dev/null || true
rm -rf "$MOUNT"; mkdir -p "$MOUNT"
ifuse --documents "$BUNDLE" "$MOUNT"
sleep 3

if [ ! -d "$MOUNT/Screenshots" ]; then
  echo "No Screenshots folder on the device yet."
  echo "Open the app, go to Settings → About & updates, tap 'Take a screenshot' (or shake the phone),"
  echo "then run this again."
  exit 0
fi

n=0
for f in "$MOUNT"/Screenshots/*.png; do
  [ -e "$f" ] || continue
  cp "$f" "$OUT/"
  n=$((n + 1))
done

fusermount -u "$MOUNT" 2>/dev/null || true

echo "Pulled $n screenshot(s) into $OUT"
ls -la "$OUT"/*.png 2>/dev/null | tail -5