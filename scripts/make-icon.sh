#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from scripts/render-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

swift scripts/render-icon.swift "$tmp/icon.png"
iconset="$tmp/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$tmp/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$tmp/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
cp "$tmp/icon.png" docs/icon.png
echo "Wrote Resources/AppIcon.icns and docs/icon.png"
