#!/bin/bash
# Assembles Sidecheck.app from a swift build output.
# Usage: ./Scripts/make_app.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="Sidecheck"
APP_DIR="build/$APP_NAME.app"

swift build -c "$CONFIG"

mkdir -p "$APP_DIR/Contents/MacOS"
cp ".build/$CONFIG/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# App icon: squircle-masked icns rendered from the icon source image.
# To change the app icon: replace Resources/logo.* with any jpg/png
# (keep exactly one) and rebuild — the icns regenerates automatically.
logos=(Resources/logo.*)
if [ "${#logos[@]}" -ne 1 ] || [ ! -f "${logos[0]}" ]; then
    echo "error: expected exactly one icon source (Resources/logo.*), add or fix it" >&2
    exit 1
fi
ICON_SRC="${logos[0]}"
ICONS_DIR="$APP_DIR/Contents/Resources"
ICNS="$ICONS_DIR/$APP_NAME.icns"
mkdir -p "$ICONS_DIR"
ICON_TMP="$(mktemp -d)"
ICONSET="$ICON_TMP/$APP_NAME.iconset"
trap 'rm -rf "$ICON_TMP"' EXIT
if [ ! -f "$ICNS" ] || [ "$ICON_SRC" -nt "$ICNS" ] || [ "Scripts/make_icon.swift" -nt "$ICNS" ]; then
    mkdir -p "$ICONSET"
    swift Scripts/make_icon.swift "$ICON_SRC" "$ICONSET/icon_512x512@2x.png"
    for size in icon_16x16:16 icon_16x16@2x:32 icon_32x32:32 icon_32x32@2x:64 \
                icon_128x128:128 icon_128x128@2x:256 icon_256x256:256 \
                icon_256x256@2x:512 icon_512x512:512; do
        name="${size%%:*}"; px="${size##*:}"
        sips -z "$px" "$px" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/$name.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICNS"
fi

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.nohan.sidecheck</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.15.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --sign - "$APP_DIR"
echo "Built $APP_DIR"
