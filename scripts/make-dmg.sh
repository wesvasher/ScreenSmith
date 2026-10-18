#!/bin/bash
# Build a Release copy of ScreenSmith and package it as a DMG for GitHub Releases.
#
# The app is ad-hoc signed and not notarized (that needs a paid Apple Developer account), so on
# first launch people have to allow it in System Settings > Privacy & Security > Open Anyway.
# The README and the release notes explain this.
#
# Usage: scripts/make-dmg.sh            builds build/ScreenSmith-<version>.dmg
#        scripts/make-dmg.sh --publish  also creates GitHub release v<version> with the DMG attached
# The version comes from MARKETING_VERSION in the Xcode project; bump it before each release.

set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build/release"
APP="$BUILD_DIR/Build/Products/Release/ScreenSmith.app"
LOG="build/release-build.log"

if [ "${1:-}" = "--publish" ]; then
    # The release tag points at the commit on GitHub, so make sure that's what gets built.
    git fetch --quiet origin
    if [ -n "$(git status --porcelain)" ] || [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "Commit and push everything to main before publishing." >&2
        exit 1
    fi
fi

echo "Building Release (Apple silicon + Intel)..."
mkdir -p build
rm -rf "$BUILD_DIR"
if ! xcodebuild -project ScreenSmith.xcodeproj -scheme ScreenSmith -configuration Release \
        -derivedDataPath "$BUILD_DIR" -destination "generic/platform=macOS" \
        CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
        build > "$LOG" 2>&1; then
    grep -E "error:" "$LOG" | sort -u >&2 || true
    echo "Build failed; see $LOG" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/ScreenSmith-$VERSION.dmg"

echo "Packaging $DMG..."
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
diskutil image create from --format UDZO --volumeName "ScreenSmith $VERSION" "$STAGING" "$DMG" > /dev/null 2>&1 \
    || { echo "Creating the disk image failed." >&2; exit 1; }

echo "Created $DMG ($(du -h "$DMG" | cut -f1)); architectures: $(lipo -archs "$APP/Contents/MacOS/ScreenSmith")"

if [ "${1:-}" = "--publish" ]; then
    TAG="v$VERSION"
    if gh release view "$TAG" > /dev/null 2>&1; then
        echo "Release $TAG already exists. Bump MARKETING_VERSION in the Xcode project first." >&2
        exit 1
    fi
    gh release create "$TAG" "$DMG" --target "$(git rev-parse HEAD)" --title "ScreenSmith $VERSION" --generate-notes \
        --notes "$(cat <<'EOF'
## Install

1. Download **ScreenSmith-*.dmg** below and open it.
2. Drag **ScreenSmith** into **Applications**.
3. Open ScreenSmith. macOS will say it can't verify the app, because it isn't notarized by Apple.
4. Go to **System Settings › Privacy & Security**, scroll down, and click **Open Anyway** next to ScreenSmith.

ScreenSmith lives in the menu bar (the display icon); it has no Dock icon. Requires macOS 26.1 or later.
EOF
)"
    echo "Published $TAG: $(gh release view "$TAG" --json url -q .url)"
fi
