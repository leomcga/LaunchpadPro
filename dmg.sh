#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="LaunchpadPro"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
STAGING_DIR="${BUILD_DIR}/dmg-staging"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

./bundle.sh

echo "==> staging DMG contents"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"
ditto "${APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> creating ${DMG_PATH}"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

if [[ -n "${SIGN_IDENTITY}" ]]; then
    echo "==> signing ${DMG_PATH}"
    codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
fi

rm -rf "${STAGING_DIR}"

echo "==> done: ${DMG_PATH}"
