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
[ -f "Resources/MayarLogo.svg" ] && cp "Resources/MayarLogo.svg" "$APP/Contents/Resources/MayarLogo.svg"

# Codesign. Defaults to ad-hoc signing so the script works out of the box on
# any machine — including forks that don't have a Developer ID. To produce a
# Gatekeeper-friendly signed build for distribution, set the env var:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" bash scripts/build-app.sh
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "→ codesign (ad-hoc)"
    codesign --force --deep --options runtime --sign - "$APP" >/dev/null
else
    if ! security find-identity -p codesigning -v 2>/dev/null | grep -qF "$SIGN_IDENTITY"; then
        echo "✗ signing identity not in keychain: $SIGN_IDENTITY"
        echo "  Install the Developer ID cert, override with SIGN_IDENTITY=...,"
        echo "  or skip signing with SIGN_IDENTITY=-"
        exit 1
    fi
    echo "→ codesign with: $SIGN_IDENTITY"
    codesign --force --deep \
        --options runtime \
        --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$APP" >/dev/null
fi

# Verify the signature is well-formed before we hand it off to the DMG step.
codesign --verify --deep --strict "$APP" 2>&1 || {
    echo "✗ codesign verify failed"; exit 1
}

echo
echo "✓ built $APP"
echo
echo "  open '$APP'                       # launch"
echo "  cp -R '$APP' /Applications/       # install"
