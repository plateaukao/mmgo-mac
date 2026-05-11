#!/usr/bin/env bash
# Build Mmgo.app — a self-contained macOS application bundle.
#
# Output: dist/Mmgo.app (overwrites any existing one).
#
# Steps:
#   1. swift build -c release
#   2. Assemble Contents/{MacOS,Frameworks,Resources}
#   3. Copy the release binary + Frameworks/libmmgo.dylib in
#   4. install_name_tool fix-up so the .app is relocatable:
#        - add @executable_path/../Frameworks rpath
#        - strip the absolute dev rpath baked in by Package.swift
#   5. Write Info.plist
#   6. Ad-hoc codesign (required on Apple Silicon to launch the bundle)

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
FRAMEWORKS_DIR="$CONTENTS/Frameworks"
RESOURCES_DIR="$CONTENTS/Resources"

SRC_BINARY=".build/release/MmgoMac"
SRC_DYLIB="Frameworks/libmmgo.dylib"

echo "==> swift build -c release"
swift build -c release

if [[ ! -f "$SRC_BINARY" ]]; then
  echo "error: expected release binary at $SRC_BINARY" >&2
  exit 1
fi
if [[ ! -f "$SRC_DYLIB" ]]; then
  echo "error: missing $SRC_DYLIB" >&2
  exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

cp "$SRC_BINARY" "$MACOS_DIR/$APP_NAME"
cp "$SRC_DYLIB" "$FRAMEWORKS_DIR/libmmgo.dylib"
chmod +x "$MACOS_DIR/$APP_NAME"

echo "==> fixing rpaths"
# Add the relocatable rpath used inside the bundle.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME"

# Strip the absolute dev rpath baked in by Package.swift (so the .app
# doesn't depend on the original checkout existing on disk). Tolerate
# the case where it isn't present.
DEV_RPATH="$PACKAGE_DIR/Frameworks"
if otool -l "$MACOS_DIR/$APP_NAME" | grep -A2 LC_RPATH | grep -q "$DEV_RPATH"; then
  install_name_tool -delete_rpath "$DEV_RPATH" "$MACOS_DIR/$APP_NAME"
fi

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
# Sign everything in one --deep pass without the hardened runtime: ad-hoc
# signatures can't satisfy the same-team-ID check that the hardened runtime
# enforces between the main binary and bundled dylibs.
codesign --force --deep --sign - --timestamp=none "$APP_DIR"

echo "==> verifying"
codesign --verify --verbose=2 "$APP_DIR"
otool -l "$MACOS_DIR/$APP_NAME" | grep -A2 LC_RPATH || true

echo ""
echo "Built: $APP_DIR"
echo "Run:   open \"$APP_DIR\""
