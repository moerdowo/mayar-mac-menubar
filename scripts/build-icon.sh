#!/usr/bin/env bash
# Build Resources/AppIcon.icns from Resources/AppIcon.svg.
# Uses only macOS-builtin tools: qlmanage, sips, iconutil.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SVG="Resources/AppIcon.svg"
OUT="Resources/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "→ rendering $SVG → 1024x1024 PNG (qlmanage)"
qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null 2>&1
MASTER="$WORK/AppIcon.svg.png"
[ -f "$MASTER" ] || { echo "qlmanage failed to produce $MASTER"; exit 1; }

# Force exact 1024x1024 (qlmanage sometimes rounds, esp. with non-integer viewBox).
sips -z 1024 1024 "$MASTER" >/dev/null

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

# Standard macOS iconset sizes — pairs of base + @2x.
declare -a SIZES=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
  size="${entry%%:*}"
  name="${entry##*:}"
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
done

echo "→ iconutil → $OUT"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "✓ wrote $OUT ($(du -h "$OUT" | cut -f1))"
