#!/usr/bin/env bash
# Update the Homebrew Cask in moerdowo/homebrew-mayar to point at the current
# version's DMG (URL + sha256). Clones the tap into build/ if not present.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NAME="MayarMenuBar"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
DMG="$ROOT/build/$NAME-$VERSION.dmg"

if [ ! -f "$DMG" ]; then
    echo "✗ DMG not found at $DMG"
    echo "  run scripts/build-dmg.sh first (or scripts/release.sh)"
    exit 1
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')

TAP_REPO="${TAP_REPO:-moerdowo/homebrew-mayar}"
TAP_DIR="${TAP_DIR:-$ROOT/build/homebrew-tap}"

echo "→ updating cask in $TAP_REPO"

if [ ! -d "$TAP_DIR/.git" ]; then
    echo "→ cloning $TAP_REPO → $TAP_DIR"
    rm -rf "$TAP_DIR"
    gh repo clone "$TAP_REPO" "$TAP_DIR"
fi

cd "$TAP_DIR"
git fetch origin main 2>/dev/null || true
git checkout main 2>/dev/null || git checkout -b main
git pull --ff-only 2>/dev/null || true

mkdir -p Casks
cat > Casks/mayar-menubar.rb <<EOF
cask "mayar-menubar" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/moerdowo/mayar-mac-menubar/releases/download/v#{version}/MayarMenuBar-#{version}.dmg"
  name "Mayar Menu Bar"
  desc "Menu bar app to check Mayar balance and transactions"
  homepage "https://github.com/moerdowo/mayar-mac-menubar"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "MayarMenuBar.app"

  zap trash: [
    "~/Library/Application Support/MayarMenuBar",
  ]

  caveats <<~CAVEATS
    The app is ad-hoc signed and not notarized. If macOS Gatekeeper blocks it,
    either right-click the app and choose Open, or run:

      xattr -dr com.apple.quarantine /Applications/MayarMenuBar.app
  CAVEATS
end
EOF

if git diff --quiet Casks/mayar-menubar.rb; then
    echo "→ cask unchanged; nothing to push"
    exit 0
fi

git add Casks/mayar-menubar.rb
git commit -m "mayar-menubar $VERSION"
git push origin main

echo
echo "✓ tap updated"
echo "  install with:"
echo "    brew tap moerdowo/mayar"
echo "    brew install --cask mayar-menubar"
