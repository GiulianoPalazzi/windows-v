#!/usr/bin/env bash
# Packages dist/Windows V.app into:
#   dist/WindowsV-<version>.zip   (drag-to-Applications archive)
#   dist/WindowsV-<version>.dmg   (drag-install disk image with /Applications link)
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_dist_app
APP="$DIST/$PRODUCT.app"

# ---- ZIP -------------------------------------------------------------------
ZIP="$DIST/WindowsV-$VERSION.zip"
log "Creating $ZIP"
rm -f "$ZIP"
( cd "$DIST" && ditto -c -k --sequesterRsrc --keepParent "$PRODUCT.app" "$ZIP" )

# ---- DMG -------------------------------------------------------------------
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ln -s /Applications "$STAGE/Applications"
ditto "$APP" "$STAGE/$PRODUCT.app"
resign_app "$STAGE/$PRODUCT.app" "$IDENTITY"

if [ -f "$ROOT/icon/WindowsV.icns" ]; then
  cp "$ROOT/icon/WindowsV.icns" "$STAGE/.VolumeIcon.icns"
fi

DMG="$DIST/WindowsV-$VERSION.dmg"
log "Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "$PRODUCT" -srcfolder "$STAGE" -ov \
  -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null

if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$DMG"
fi

log "Verifying packaged artifacts..."
rm -rf "$STAGE/_verify"
(ditto -x -k "$ZIP" "$STAGE/_verify" && verify_after_copy "$STAGE/_verify/$PRODUCT.app") || {
  error "zip contents fail signature verification"
  exit 1
}
MOUNT="$(hdiutil attach -nobrowse -readonly "$DMG" | awk -F'\t' '/\/Volumes\// {print $NF}' | head -1)"
if [ -n "$MOUNT" ]; then
  verify_after_copy "$MOUNT/$PRODUCT.app"
  hdiutil detach "$MOUNT" >/dev/null
fi

log "done:"
log "  $ZIP"
log "  $DMG"
