#!/usr/bin/env bash
# PopShot installer.
#   Install:   curl -fsSL https://raw.githubusercontent.com/bobdabuildrr/PopShot/main/scripts/install.sh | bash
#   Uninstall: curl -fsSL https://raw.githubusercontent.com/bobdabuildrr/PopShot/main/scripts/install.sh | bash -s -- --uninstall
# Options (environment variables):
#   POPSHOT_DEST=~/Applications   install somewhere else (no admin password needed)
#   POPSHOT_ZIP_URL=…             install a specific build instead of the latest release
set -euo pipefail

REPO="bobdabuildrr/PopShot"
ZIP_URL="${POPSHOT_ZIP_URL:-https://github.com/$REPO/releases/latest/download/PopShot.zip}"
APP="PopShot.app"
BUNDLE_ID="app.popshot.PopShot"
DEST="${POPSHOT_DEST:-/Applications}"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
as_admin() { if [ -w "$DEST" ]; then "$@"; else sudo "$@"; fi; }

# SIGTERM lets PopShot restore Apple's thumbnail setting itself; force-quit if it takes over 10 s.
quit_popshot() {
  pgrep -x PopShot >/dev/null || return 0
  pkill -TERM -x PopShot || true
  for _ in $(seq 1 50); do pgrep -x PopShot >/dev/null || return 0; sleep 0.2; done
  pkill -KILL -x PopShot || true
}

if [ "${1:-}" = "--uninstall" ]; then
  quit_popshot
  # Put Apple's floating thumbnail back if PopShot didn't get the chance to.
  case "$(defaults read "$BUNDLE_ID" thumbnailOriginal 2>/dev/null || true)" in
    unset) defaults delete com.apple.screencapture show-thumbnail 2>/dev/null || true ;;
    true)  defaults write com.apple.screencapture show-thumbnail -bool true ;;
  esac
  as_admin rm -rf "${DEST:?}/$APP"
  rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
  defaults delete "$BUNDLE_ID" 2>/dev/null || true
  say "PopShot uninstalled."
  exit 0
fi

[ "$(uname)" = "Darwin" ] || { echo "PopShot is a macOS app."; exit 1; }
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 13 ]; then
  echo "PopShot needs macOS 13 Ventura or later."
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "Downloading PopShot…"
curl -fL --progress-bar "$ZIP_URL" -o "$tmp/PopShot.zip"
ditto -x -k "$tmp/PopShot.zip" "$tmp"

quit_popshot
mkdir -p "$DEST" 2>/dev/null || true
say "Installing to $DEST…"
as_admin rm -rf "${DEST:?}/$APP"
as_admin ditto "$tmp/$APP" "$DEST/$APP"
# curl doesn't add the quarantine flag; clear it anyway in case the zip came from a browser.
as_admin xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

open "$DEST/$APP"
say "Done! PopShot is in your menu bar. Press ⌘⇧4 to try it."
