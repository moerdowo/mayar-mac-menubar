#!/usr/bin/env bash
# Build a distribution DMG that contains MayarMenuBar.app + a symlink to
# /Applications, so users can drag-install in the usual macOS way. Uses only
# built-in tools (hdiutil, shasum) — no Homebrew dependency.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="MayarMenuBar"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo "0.1.0")"
APP="$ROOT/build/$NAME.app"
STAGING="$ROOT/build/dmg-staging"
DMG="$ROOT/build/$NAME-$VERSION.dmg"

# Build the .app first if it isn't already.
if [ ! -d "$APP" ]; then
    echo "→ no .app at $APP — running build-app.sh"
    bash "$ROOT/scripts/build-app.sh"
fi

echo "→ staging DMG contents in $STAGING"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/$NAME.app"
ln -s /Applications "$STAGING/Applications"

echo "→ creating $DMG"
rm -f "$DMG"
hdiutil create \
    -volname "$NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

rm -rf "$STAGING"

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
SIZE=$(du -h "$DMG" | cut -f1)

echo
echo "✓ wrote $DMG  ($SIZE)"
echo "  sha256: $SHA"
echo
echo "  open '$DMG'   # try the install dialog locally"
