#!/usr/bin/env bash
# Builds the Release app and stages it as dist/Windows V.app.
#
# Signing:
#   IDENTITY=...            codesign identity (default: ad-hoc "-")
#   For a notarizable, distributable build pass your Developer ID, e.g.
#     IDENTITY="Developer ID Application: Your Name (TEAMID)" make build
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED="$ROOT/build"

log "Building $PRODUCT ($CONFIGURATION) with identity '$IDENTITY'..."
xcodebuild -project "$PROJECT" -scheme "$TARGET" -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build

APP="$DERIVED/Build/Products/$CONFIGURATION/$TARGET.app"
[ -d "$APP" ] || { error "build did not produce $APP"; exit 1; }

mkdir -p "$DIST"
DST="$DIST/$PRODUCT.app"
rm -rf "$DST"
ditto "$APP" "$DST"

log "Signing staged app (identity '$IDENTITY')..."
resign_app "$DST" "$IDENTITY"
verify_after_copy "$DST"
spctl --assess --type execute "$DST" 2>/dev/null || warn "Gatekeeper assessment pending (expected for ad-hoc/dev builds)"

log "ok: $DST"
