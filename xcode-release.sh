#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="LaunchpadPro"
PROJECT_PATH="${APP_NAME}.xcodeproj"
SCHEME="${APP_NAME}"
CONFIGURATION="Release"
ARCHIVE_PATH="build/archives/${APP_NAME}.xcarchive"
EXPORT_PATH="build/export-xcode"
NOTARIZED_EXPORT_PATH="build/notarized-xcode"
STAGING_DIR="build/dmg-staging"
DMG_PATH="build/${APP_NAME}.dmg"
EXPORT_OPTIONS="Support/ExportOptions-DeveloperID.plist"
UPLOAD_FOR_NOTARIZATION="${UPLOAD_FOR_NOTARIZATION:-0}"
USE_NOTARIZED_APP="${USE_NOTARIZED_APP:-0}"

rm -rf "${STAGING_DIR}"
mkdir -p "build/archives"

if [[ "${USE_NOTARIZED_APP}" != "1" ]]; then
    rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"

    echo "==> archiving universal app with Xcode automatic signing"
    xcodebuild \
        -project "${PROJECT_PATH}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -destination "generic/platform=macOS" \
        -archivePath "${ARCHIVE_PATH}" \
        -allowProvisioningUpdates \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        archive

    echo "==> exporting Developer ID signed app"
    xcodebuild \
        -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS}" \
        -allowProvisioningUpdates
fi

if [[ "${UPLOAD_FOR_NOTARIZATION}" == "1" ]]; then
    upload_options="$(mktemp "${TMPDIR:-/tmp}/launchpadpro-upload-options.XXXXXX.plist")"
    cp "${EXPORT_OPTIONS}" "${upload_options}"
    /usr/libexec/PlistBuddy -c "Set :destination upload" "${upload_options}" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :destination string upload" "${upload_options}"

    echo "==> uploading archive for Apple notarization"
    xcodebuild \
        -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "build/upload-xcode" \
        -exportOptionsPlist "${upload_options}" \
        -allowProvisioningUpdates
    rm -f "${upload_options}"

    echo "==> notarization submitted; rerun with USE_NOTARIZED_APP=1 after processing finishes"
fi

app_source="${EXPORT_PATH}/${APP_NAME}.app"
if [[ "${USE_NOTARIZED_APP}" == "1" ]]; then
    rm -rf "${NOTARIZED_EXPORT_PATH}"
    echo "==> exporting notarized app"
    xcodebuild \
        -exportNotarizedApp \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${NOTARIZED_EXPORT_PATH}"
    app_source="${NOTARIZED_EXPORT_PATH}/${APP_NAME}.app"
fi

echo "==> creating ${DMG_PATH}"
rm -rf "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"
ditto "${app_source}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"
rm -rf "${STAGING_DIR}"

echo "==> verifying"
lipo -info "${app_source}/Contents/MacOS/${APP_NAME}"
codesign --verify --deep --strict --verbose=2 "${app_source}"
hdiutil verify "${DMG_PATH}"

echo "==> done: ${DMG_PATH}"
