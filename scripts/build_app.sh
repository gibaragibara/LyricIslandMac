#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="LyricIslandMac"
CONFIGURATION="${CONFIGURATION:-release}"
DOTNET_CONFIGURATION="${DOTNET_CONFIGURATION:-Release}"
TARGET_FRAMEWORK="${TARGET_FRAMEWORK:-net10.0}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPER_SOURCE_DIR="$ROOT_DIR/lyrics-service/LyricIsland.LyricsService/bin/$DOTNET_CONFIGURATION/$TARGET_FRAMEWORK"
HELPER_TARGET_DIR="$RESOURCES_DIR/LyricsService"

mkdir -p "$DIST_DIR"

echo "==> Building Swift app ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --package-path "$ROOT_DIR" --product "$APP_NAME"
SWIFT_BIN_DIR="$(swift build -c "$CONFIGURATION" --package-path "$ROOT_DIR" --show-bin-path)"
SWIFT_EXECUTABLE="$SWIFT_BIN_DIR/$APP_NAME"

if [[ ! -f "$SWIFT_EXECUTABLE" ]]; then
  echo "Swift executable not found at $SWIFT_EXECUTABLE" >&2
  exit 1
fi

echo "==> Building .NET lyrics helper ($DOTNET_CONFIGURATION)"
dotnet build "$ROOT_DIR/lyrics-service/LyricIsland.LyricsService/LyricIsland.LyricsService.csproj" -c "$DOTNET_CONFIGURATION"

if [[ ! -d "$HELPER_SOURCE_DIR" ]]; then
  echo "Lyrics helper output directory not found at $HELPER_SOURCE_DIR" >&2
  exit 1
fi

echo "==> Assembling app bundle"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$SWIFT_EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
mkdir -p "$HELPER_TARGET_DIR"
cp -R "$HELPER_SOURCE_DIR"/. "$HELPER_TARGET_DIR/"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>LyricIslandMac</string>
  <key>CFBundleIdentifier</key>
  <string>com.gibaragibara.LyricIslandMac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LyricIslandMac</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "App bundle created at: $APP_DIR"
