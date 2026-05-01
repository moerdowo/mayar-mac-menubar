#!/usr/bin/env bash
# Build MayarMenuBar.app — a proper macOS bundle that can live in /Applications
# and register as a login item via SMAppService.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="MayarMenuBar"
APP="$ROOT/build/$NAME.app"

echo "→ swift build -c release"
swift build -c release

echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$NAME" "$APP/Contents/MacOS/$NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ ! -f "Resources/AppIcon.icns" ]; then
  echo "→ Resources/AppIcon.icns missing — generating"
  bash "$ROOT/scripts/build-icon.sh"
fi
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign. SMAppService (Launch at Login) refuses unsigned bundles, and
# Gatekeeper is friendlier with at least a signature even if it's `-`.
echo "→ codesign --sign -"
codesign --force --deep --options runtime --sign - "$APP" >/dev/null

echo
echo "✓ built $APP"
echo
echo "  open '$APP'                       # launch"
echo "  cp -R '$APP' /Applications/       # install"
echo "  xattr -dr com.apple.quarantine '$APP'   # if Gatekeeper complains"
