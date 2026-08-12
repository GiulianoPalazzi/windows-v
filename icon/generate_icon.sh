#!/usr/bin/env bash
# Generates every macOS AppIcon size from icon/AppIcon.svg into the asset catalog,
# plus a standalone WindowsV.icns for use outside the app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="$ROOT/icon/AppIcon.svg"
SET="$ROOT/ClipboardManager/Resources/Assets.xcassets/AppIcon.appiconset"

command -v rsvg-convert >/dev/null || { echo "error: rsvg-convert not found (brew install librsvg)"; exit 1; }

render() { # render <size> <outfile>
  rsvg-convert -w "$1" -h "$1" -o "$2" "$SVG"
}

declare -a SIZES=(16 32 32 64 128 256 256 512 512 1024)
declare -a NAMES=(icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
                  icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png \
                  icon_512x512.png icon_512x512@2x.png)

for i in "${!SIZES[@]}"; do
  render "${SIZES[$i]}" "$SET/${NAMES[$i]}"
  echo "wrote ${NAMES[$i]} (${SIZES[$i]}x${SIZES[$i]})"
done

ICONSET_DIR="$(mktemp -d)"
ICONSET="$ICONSET_DIR/WindowsV.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$ICONSET_DIR"' EXIT
for s in 16 32 128 256 512; do
  cp "$SET/icon_${s}x${s}.png" "$ICONSET/icon_${s}x${s}.png"
  cp "$SET/icon_${s}x${s}@2x.png" "$ICONSET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$ROOT/icon/WindowsV.icns"
echo "wrote icon/WindowsV.icns"
