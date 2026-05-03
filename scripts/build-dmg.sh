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

# Sign the DMG (so its own signature is verifiable) and submit for
# notarization. Notarization checks the .app inside as well as the DMG
# wrapper. After Apple's notary service approves, we staple the ticket
# so the DMG launches cleanly without an internet connection.
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: PT Mayar Kernel Supernova (3393MGXACK)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-MAYAR_NOTARY}"

if [ "$SIGN_IDENTITY" = "-" ] || [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "→ skipping DMG signing + notarization (SIGN_IDENTITY=$SIGN_IDENTITY SKIP_NOTARIZE=${SKIP_NOTARIZE:-0})"
else
    echo "→ codesign DMG with: $SIGN_IDENTITY"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG" >/dev/null

    echo "→ notarize via profile '$NOTARY_PROFILE' (this can take a few minutes)"
    if ! xcrun notarytool submit "$DMG" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --output-format json > /tmp/notary-result.json; then
        echo "✗ notarytool submit failed"
        cat /tmp/notary-result.json
        echo
        echo "  Run: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
        exit 1
    fi
    STATUS=$(/usr/bin/grep -o '"status":"[^"]*"' /tmp/notary-result.json | head -1 | cut -d'"' -f4)
    if [ "$STATUS" != "Accepted" ]; then
        echo "✗ notarization status: $STATUS"
        cat /tmp/notary-result.json
        SUB_ID=$(/usr/bin/grep -o '"id":"[^"]*"' /tmp/notary-result.json | head -1 | cut -d'"' -f4)
        echo
        echo "  Run: xcrun notarytool log $SUB_ID --keychain-profile $NOTARY_PROFILE"
        exit 1
    fi
    echo "→ notarization Accepted; stapling ticket"
    xcrun stapler staple "$DMG" >/dev/null
    xcrun stapler validate "$DMG" >/dev/null
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
SIZE=$(du -h "$DMG" | cut -f1)

echo
echo "✓ wrote $DMG  ($SIZE)"
echo "  sha256: $SHA"
echo
echo "  open '$DMG'   # try the install dialog locally"
