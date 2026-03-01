#!/usr/bin/env bash
# make_dmg.sh — sestaví Dictate.app a zabalí do čistého DMG (drag-to-Applications)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-1.0}"
APP_NAME="Dictate"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/${APP_NAME}.app"
STAGING="$BUILD_DIR/dmg_staging"

echo "==> Sestavuji ${APP_NAME} ${VERSION}…"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

# Kompilace
swiftc "$SCRIPT_DIR/Dictate.swift" \
    -o "$APP_PATH/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework AVFoundation \
    -target arm64-apple-macos13.0 \
    -O

# Vložení dictate.sh do bundlu (Resources)
cp "$SCRIPT_DIR/dictate.sh" "$APP_PATH/Contents/Resources/dictate.sh"
chmod +x "$APP_PATH/Contents/Resources/dictate.sh"

# Ikona aplikace
cp "$SCRIPT_DIR/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"

# Info.plist
cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.0x0ndra.dictate</string>
    <key>CFBundleName</key>
    <string>Dictate</string>
    <key>CFBundleExecutable</key>
    <string>Dictate</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Dictate potřebuje přístup k mikrofonu pro nahrávání řeči.</string>
</dict>
</plist>
PLIST

# Staging: jen .app + Applications symlink (čistý drag-to-install)
echo "==> Připravuji DMG staging…"
mkdir -p "$STAGING"
cp -r "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Vytvoření writable DMG, positioning ikon, finální komprese
TMPFILE="$BUILD_DIR/tmp_rw.dmg"
DMG_W=520; DMG_H=300
APP_X=130; APP_Y=150
LINK_X=390; LINK_Y=150

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDRW -fs HFS+ "$TMPFILE" > /dev/null

MOUNT_OUTPUT=$(hdiutil attach "$TMPFILE" -readwrite -noverify -noautoopen)
MOUNT_DEV=$(echo "$MOUNT_OUTPUT" | grep -E '/dev/disk[0-9]+\b' | head -1 | awk '{print $1}')
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | awk '{print $NF}')

osascript <<APPLESCRIPT > /dev/null 2>&1
tell application "Finder"
    tell disk "${APP_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, $((200+DMG_W)), $((200+DMG_H))}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "${APP_NAME}.app" of container window to {${APP_X}, ${APP_Y}}
        set position of item "Applications" of container window to {${LINK_X}, ${LINK_Y}}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT_DEV" > /dev/null

# Komprimovaný finální DMG
hdiutil convert "$TMPFILE" -format UDZO -imagekey zlib-level=9 -o "$SCRIPT_DIR/$DMG_NAME" > /dev/null

rm -rf "$BUILD_DIR"
echo "==> ✓ Hotovo: $DMG_NAME ($(du -sh "$SCRIPT_DIR/$DMG_NAME" | cut -f1))"
echo "    Model patří do: ~/Library/Application Support/Dictate/models/ggml-large-v3-turbo.bin"
