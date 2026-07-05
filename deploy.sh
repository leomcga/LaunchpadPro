#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="LaunchpadPro"
EXECUTABLE_NAME="LaunchpadProCodex"
APP_PATH="/Applications/${APP_NAME}.app"
OLD_APP_PATH="/Applications/LaunchpadProCodex.app"

./bundle.sh

echo "==> quitting old ${APP_NAME} instances"
osascript -e 'tell application "LaunchpadPro" to quit' 2>/dev/null || true
osascript -e 'tell application "LaunchpadProCodex" to quit' 2>/dev/null || true
killall -9 "${APP_NAME}" 2>/dev/null || true
killall -9 "${EXECUTABLE_NAME}" 2>/dev/null || true
pkill -9 -f "${APP_PATH}" 2>/dev/null || true
pkill -9 -f "${OLD_APP_PATH}" 2>/dev/null || true
sleep 1

echo "==> installing ${APP_PATH}"
rm -rf "${APP_PATH}"
rm -rf "${OLD_APP_PATH}"
cp -R "build/${APP_NAME}.app" "${APP_PATH}"
xattr -dr com.apple.quarantine "${APP_PATH}" 2>/dev/null || true

LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "${APP_PATH}" 2>/dev/null || true

echo "==> launching"
open -a "${APP_PATH}"
sleep 2

if pgrep -fl "${APP_PATH}" >/dev/null; then
    echo "==> running: $(stat -f '%Sm' "${APP_PATH}/Contents/MacOS/${EXECUTABLE_NAME}")"
else
    echo "==> WARNING: ${APP_NAME} is not running"
fi
