#!/usr/bin/env bash
# Notarizes the packaged zip, staples the app, repackages so the staple is
# inside, then notarizes + staples the DMG.
#
# Credentials (pick one):
#   KEYCHAIN_PROFILE="WindowsV"            keychain item stored via
#                                          `xcrun notarytool store-credentials`
#   APPLE_ID + APPLE_PASSWORD + APPLE_TEAM_ID
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

require_dist_app

if [ -n "${APPLE_ID:-}" ]; then
  CREDS=(--apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID")
elif [ -n "${KEYCHAIN_PROFILE:-}" ]; then
  CREDS=(--keychain-profile "$KEYCHAIN_PROFILE")
else
  error "no credentials: set KEYCHAIN_PROFILE=... or APPLE_ID/APPLE_PASSWORD/APPLE_TEAM_ID"
  exit 1
fi

ZIP="$DIST/WindowsV-$VERSION.zip"
[ -f "$ZIP" ] || { error "missing $ZIP — run 'make package' first"; exit 1; }

log "Submitting $ZIP to Apple notary..."
xcrun notarytool submit "$ZIP" "${CREDS[@]}" --wait || { error "notarization failed"; exit 1; }

log "Stapling $PRODUCT.app..."
xcrun stapler staple "$DIST/$PRODUCT.app"

# Repackage so the stapled app is inside the zip and dmg.
log "Repackaging with staple..."
rm -f "$ZIP" "$DIST/WindowsV-$VERSION.dmg"
"$ROOT/scripts/package.sh"

DMG="$DIST/WindowsV-$VERSION.dmg"
log "Submitting $DMG to Apple notary..."
xcrun notarytool submit "$DMG" "${CREDS[@]}" --wait || { error "dmg notarization failed"; exit 1; }
log "Stapling $DMG..."
xcrun stapler staple "$DMG"

log "Notarization complete:"
log "  $ZIP"
log "  $DMG"
