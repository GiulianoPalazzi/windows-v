#!/usr/bin/env bash
# Shared helpers for the Windows V build toolchain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PRODUCT="Windows V"
TARGET="ClipboardManager"
PROJECT="$ROOT/ClipboardManager.xcodeproj"
PLIST="$ROOT/ClipboardManager/Resources/Info.plist"
DIST="$ROOT/dist"

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")"
VERSION="$SHORT_VERSION"

# Codesign identity. Ad-hoc ("-") by default; set a Developer ID for
# notarizable distribution: IDENTITY="Developer ID Application: Name (TEAMID)"
IDENTITY="${IDENTITY:--}"

log()   { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[build]\033[0m %s\n' "$*" >&2; }
error() { printf '\033[1;31m[build]\033[0m %s\n' "$*" >&2; }

require_dist_app() {
  [ -d "$DIST/$PRODUCT.app" ] || {
    error "missing $DIST/$PRODUCT.app — run 'make build' first"
    exit 1
  }
}

# Re-sign an app bundle after staging/copying. --deep re-seals the main
# executable and nested code so copies verify cleanly (macOS 26 quirk).
resign_app() { # resign_app <path-to.app> <identity>
  local app="$1"
  local ident="${2:--}"
  local opts=()
  if [ "$ident" != "-" ]; then
    opts=(--options runtime)
  fi
  codesign --force --deep --sign "$ident" ${opts[@]+"${opts[@]}"} "$app"
}

verify_after_copy() { # verify the app works once copied, and is present in zip/dmg
  local app="$1"
  codesign --verify --deep --strict "$app" || {
    error "signature invalid after copy: $app"
    exit 1
  }
}
