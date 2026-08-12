#!/usr/bin/env bash
# Reads or bumps the app version in ClipboardManager/Resources/Info.plist.
#
#   version.sh show
#   version.sh set 1.2.0          (also bumps build number to 1200+n)
#   version.sh patch              (1.0.0 -> 1.0.1)
#   version.sh minor              (1.0.0 -> 1.1.0)
#   version.sh major              (1.0.0 -> 2.0.0)
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
BUDDY=/usr/libexec/PlistBuddy

cmd="${1:-show}"

case "$cmd" in
  show)
    echo "version: $SHORT_VERSION (build $BUILD_NUMBER)"
    ;;
  set)
    [ $# -ge 2 ] || { error "usage: version.sh set X.Y.Z"; exit 1; }
    NEW="$2"
    BUILD="$(date +%Y%m%d)"
    $BUDDY -c "Set :CFBundleShortVersionString $NEW" "$PLIST"
    $BUDDY -c "Set :CFBundleVersion $BUILD" "$PLIST"
    echo "set $NEW (build $BUILD)"
    ;;
  patch|minor|major)
    IFS='.' read -r -a parts <<< "$SHORT_VERSION"
    [[ "$SHORT_VERSION" == *.*.* ]] || parts+=("0")
    case "$cmd" in
      patch) parts[2]=$(( ${parts[2]:-0} + 1 ));;
      minor) parts[1]=$(( ${parts[1]:-0} + 1 )); parts[2]=0;;
      major) parts[0]=$(( parts[0] + 1 )); parts[1]=0; parts[2]=0;;
    esac
    NEW="${parts[0]}.${parts[1]}.${parts[2]}"
    BUILD="$(date +%Y%m%d)"
    $BUDDY -c "Set :CFBundleShortVersionString $NEW" "$PLIST"
    $BUDDY -c "Set :CFBundleVersion $BUILD" "$PLIST"
    echo "bumped to $NEW (build $BUILD)"
    ;;
  *)
    error "unknown command: $cmd (use show|set|patch|minor|major)"
    exit 1
    ;;
esac
