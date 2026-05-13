#!/usr/bin/env bash
# Build Mmgo.app — a self-contained macOS application bundle.
#
# Output: dist/Mmgo.app (overwrites any existing one).
#
# Steps:
#   1. swift build -c release
#   2. Assemble Contents/{MacOS,Resources}
#   3. Copy the release binary + SwiftPM resource bundle (mermaid.js + html)
#   4. Write Info.plist
#   5. Ad-hoc codesign (required on Apple Silicon to launch the bundle)

set -euo pipefail

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PACKAGE_DIR"

APP_NAME="Mmgo"
BUNDLE_ID="com.danielkao.mmgo"
VERSION="0.1.0"
BUILD="1"
MIN_MACOS="14.0"

DIST_DIR="$PACKAGE_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

SRC_BINARY=".build/release/MmgoMac"
SRC_RESOURCE_BUNDLE=".build/release/MmgoMac_MmgoMac.bundle"

echo "==> swift build -c release"
swift build -c release

if [[ ! -f "$SRC_BINARY" ]]; then
  echo "error: expected release binary at $SRC_BINARY" >&2
  exit 1
fi
if [[ ! -d "$SRC_RESOURCE_BUNDLE" ]]; then
  echo "error: missing $SRC_RESOURCE_BUNDLE (Bundle.module resources)" >&2
  exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$SRC_BINARY" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Bundle.module also searches Contents/Resources; placing the bundle there
# keeps codesign --deep happy (a sub-bundle in Contents/MacOS is treated as
# a malformed helper).
cp -R "$SRC_RESOURCE_BUNDLE" "$RESOURCES_DIR/"

echo "==> writing Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
codesign --force --deep --sign - --timestamp=none "$APP_DIR"

echo "==> verifying"
codesign --verify --verbose=2 "$APP_DIR"

echo ""
echo "Built: $APP_DIR"
echo "Run:   open \"$APP_DIR\""
