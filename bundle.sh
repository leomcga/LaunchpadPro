#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="LaunchpadPro"
EXECUTABLE_NAME="LaunchpadProCodex"
DISPLAY_NAME="LaunchpadPro"
BUNDLE_ID="com.leo.launchpadprocodex"
MARKETING_VERSION="1.2.0"
BUILD_NUMBER="2"
BUILD_DIR=".build/apple/Products/Release"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

echo "==> swift build -c release --arch arm64 --arch x86_64"
swift build -c release --arch arm64 --arch x86_64

echo "==> assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp "${BUILD_DIR}/${EXECUTABLE_NAME}" "${CONTENTS}/MacOS/${EXECUTABLE_NAME}"
cp "Resources/AppIcon.icns" "${CONTENTS}/Resources/AppIcon.icns"
cp "Resources/AppIcon.png" "${CONTENTS}/Resources/AppIcon.png"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key> <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key> <string>${DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key> <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key> <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key> <string>AppIcon</string>
    <key>CFBundleVersion</key> <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key> <string>${MARKETING_VERSION}</string>
    <key>CFBundlePackageType</key> <string>APPL</string>
    <key>LSMinimumSystemVersion</key> <string>26.0</string>
    <key>LSUIElement</key> <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key> <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key> <string>${BUNDLE_ID}</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>launchpadpro</string>
                <string>launchpadprocodex</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_IDENTITY}" ]]; then
    echo "==> signing with ${SIGN_IDENTITY}"
    codesign --force --deep --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${APP_DIR}"
else
    echo "==> ad-hoc signing"
    codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || codesign --force --sign - "${APP_DIR}"
fi

echo "==> done: ${APP_DIR}"
