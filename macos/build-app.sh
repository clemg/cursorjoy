#!/bin/bash
#
#   ./build-app.sh            # builds the .app and a plain DMG (build/dist/)
#   ./build-app.sh -app-only  # builds just the .app
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="CursorJoy"
VERSION="${2:-0.1.0}"
MODE="${1:-dmg}"

echo "==> Building Swift package (release)"
swift build -c release

APP_DIR="build/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"
printf 'APPL????' >"$APP_DIR/Contents/PkgInfo"
cp Support/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "==> Built: $APP_DIR"

if [ "$MODE" = "-app-only" ]; then
  exit 0
fi

echo "==> Building plain DMG"
rm -rf build/stage build/dist
mkdir -p build/stage build/dist
cp -R "$APP_DIR" build/stage/
ln -s /Applications build/stage/Applications
hdiutil create -volname "$APP_NAME" -srcfolder build/stage \
  -ov -format UDZO "build/dist/$APP_NAME-$VERSION.dmg" >/dev/null
rm -rf build/stage

echo "==> Done: build/dist/$APP_NAME-$VERSION.dmg"
