#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

APP_NAME="Nooklings"
# Keep the installed app identity so existing preferences and Keychain access survive.
BUNDLE_ID="com.ronnie.byte"
BIN="Nooklings"
APP_DIR="${APP_NAME}.app"
ICON_SOURCE="docs/assets/nooklings-icon.png"

echo "> Building release binary..."
swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"

echo "> Assembling ${APP_DIR} ..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${BUILD_DIR}/${BIN}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
# Bundle the companion artwork for standalone installs.
RESOURCE_BUNDLE="${BUILD_DIR}/Nooklings_Byte.bundle"
if [ ! -d "${RESOURCE_BUNDLE}" ]; then
  echo "Missing companion resource bundle: ${RESOURCE_BUNDLE}" >&2
  exit 1
fi
cp -R "${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/"

ICON_KEY=""
if command -v iconutil >/dev/null 2>&1 && command -v sips >/dev/null 2>&1 && [ -f "${ICON_SOURCE}" ]; then
  echo "> Building app icon..."
  ICON_WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "${ICON_WORK_DIR}"' EXIT
  ICONSET="${ICON_WORK_DIR}/${APP_NAME}.iconset"
  mkdir -p "${ICONSET}"
  for size in 16 32 128 256 512; do
    sips --resampleHeightWidth "${size}" "${size}" "${ICON_SOURCE}" \
      --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips --resampleHeightWidth "${retina}" "${retina}" "${ICON_SOURCE}" \
      --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${APP_DIR}/Contents/Resources/${APP_NAME}.icns"
  ICON_KEY="  <key>CFBundleIconFile</key><string>${APP_NAME}</string>"
  echo "  icon installed"
else
  echo "> Skipping icon (iconutil, sips, or ${ICON_SOURCE} not found)"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
${ICON_KEY}
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo ""
echo "[OK] Built ${APP_DIR}"
echo "   Next:"
echo "   1. mv \"${APP_DIR}\" /Applications/"
echo "   2. Launch ${APP_NAME}, click the gear, toggle 'Launch at login'"
echo "      (or add it manually: System Settings -> General -> Login Items)"
echo "   (Unsigned, so on first launch: right-click ${APP_NAME} -> Open, or run"
echo "    'xattr -dr com.apple.quarantine /Applications/${APP_DIR}')"
echo ""
echo "   If the icon doesn't refresh in Finder/Dock, run:"
echo "   touch \"/Applications/${APP_DIR}\" && killall Finder Dock"
