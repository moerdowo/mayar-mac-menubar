#!/usr/bin/env bash
# Cut a GitHub release for the current Info.plist version. Tags HEAD as
# v<version>, builds the DMG if needed, uploads it as the release asset.
# Idempotent: re-running on an existing tag/release re-uploads the asset.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="MayarMenuBar"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
DMG="$ROOT/build/$NAME-$VERSION.dmg"

# Build DMG if missing.
if [ ! -f "$DMG" ]; then
    echo "→ DMG not found; building"
    bash "$ROOT/scripts/build-dmg.sh"
fi

# Tag HEAD if no such tag yet.
if git rev-parse --verify "$TAG" >/dev/null 2>&1; then
    echo "→ tag $TAG already exists locally"
else
    echo "→ tagging $TAG"
    git tag -a "$TAG" -m "Release $TAG"
fi

# Push tag to origin if it isn't there yet.
if ! git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
    git push origin "$TAG"
fi

# Create or update the GitHub release.
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "→ release $TAG exists; uploading asset (clobber)"
    gh release upload "$TAG" "$DMG" --clobber
else
    echo "→ creating release $TAG"
    gh release create "$TAG" "$DMG" \
        --title "$NAME $VERSION" \
        --generate-notes
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
URL="https://github.com/moerdowo/mayar-mac-menubar/releases/download/$TAG/$(basename "$DMG")"

echo
echo "✓ released $TAG"
echo "  asset url: $URL"
echo "  sha256:    $SHA"
echo
echo "  next: bash scripts/update-cask.sh   # to refresh the Homebrew tap"
