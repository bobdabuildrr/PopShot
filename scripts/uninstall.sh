#!/usr/bin/env bash
# Removes PopShot and puts macOS's screenshot settings back the way they were.
# Usage: ./scripts/uninstall.sh [--purge]   (--purge also deletes PopShot's preferences)
set -euo pipefail
BUNDLE_ID="app.popshot.PopShot"

"$(dirname "$0")/quit-running.sh"

# Safety net in case PopShot didn't get to restore Apple's floating thumbnail itself.
original="$(defaults read "$BUNDLE_ID" thumbnailOriginal 2>/dev/null || true)"
case "$original" in
  unset) defaults delete com.apple.screencapture show-thumbnail 2>/dev/null || true ;;
  true)  defaults write com.apple.screencapture show-thumbnail -bool true ;;
esac
defaults delete "$BUNDLE_ID" thumbnailOriginal 2>/dev/null || true

for app in "/Applications/PopShot.app" "$HOME/Applications/PopShot.app"; do
  if [ -d "$app" ]; then
    if [ -w "$(dirname "$app")" ]; then rm -rf "$app"; else sudo rm -rf "$app"; fi
  fi
done
rm -f "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

if [ "${1:-}" = "--purge" ]; then
  defaults delete "$BUNDLE_ID" 2>/dev/null || true
fi
echo "PopShot uninstalled."
