#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="LyricIslandMac"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME}"
STAGING_DIR="$DIST_DIR/dmg-root"
TEMP_DMG_PATH="$DIST_DIR/$APP_NAME-temp.dmg"
INSTALL_HINT_FILE="拖动到 Applications 文件夹完成安装.txt"
DEVICE=""

"$ROOT_DIR/scripts/build_app.sh"

echo "==> Creating DMG"
rm -f "$DMG_PATH"
rm -f "$TEMP_DMG_PATH"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/$INSTALL_HINT_FILE" <<EOF
安装方式：

1. 将左侧的 $APP_NAME.app 拖动到右侧 Applications 文件夹
2. 打开“应用程序”启动 $APP_NAME
EOF

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -ov \
  -format UDRW \
  "$TEMP_DMG_PATH"

MOUNT_OUTPUT="$(hdiutil attach "$TEMP_DMG_PATH" -noverify -noautoopen)"
DEVICE="$(echo "$MOUNT_OUTPUT" | awk '/^\/dev\// {print $1; exit}')"
MOUNT_POINT="/Volumes/$VOLUME_NAME"

cleanup_mount() {
  if [[ -n "${DEVICE:-}" ]]; then
    hdiutil detach "$DEVICE" >/dev/null 2>&1 || hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
  fi
}

trap cleanup_mount EXIT

if [[ -n "${DEVICE:-}" && -d "$MOUNT_POINT" ]]; then
  if osascript <<EOF >/dev/null 2>&1
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 920, 520}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 144
    set text size of theViewOptions to 16
    set position of item "$APP_NAME.app" to {180, 220}
    set position of item "Applications" to {560, 220}
    set position of item "$INSTALL_HINT_FILE" to {360, 70}
    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
end tell
EOF
  then
    echo "Configured DMG Finder layout"
  else
    echo "Skipping Finder layout customization"
  fi

  sync
fi

cleanup_mount
DEVICE=""
hdiutil convert "$TEMP_DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
trap - EXIT
rm -f "$TEMP_DMG_PATH"

rm -rf "$STAGING_DIR"

echo "DMG created at: $DMG_PATH"
