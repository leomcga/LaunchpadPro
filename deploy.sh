#!/bin/bash
# Build, fully quit any running instance, install to /Applications, relaunch.
# The kill-first step is essential: LaunchpadPro is a persistent menu-bar agent,
# and `open` will re-activate an already-running (old) instance instead of
# launching the freshly built binary.
set -euo pipefail
cd "$(dirname "$0")"

./bundle.sh

echo "==> quitting all running instances"
osascript -e 'tell application "LaunchpadPro" to quit' 2>/dev/null || true
killall -9 LaunchpadPro 2>/dev/null || true
pkill -9 -f LaunchpadPro 2>/dev/null || true
sleep 1

echo "==> installing to /Applications"
rm -rf /Applications/LaunchpadPro.app
cp -R build/LaunchpadPro.app /Applications/LaunchpadPro.app
xattr -dr com.apple.quarantine /Applications/LaunchpadPro.app 2>/dev/null || true

LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f /Applications/LaunchpadPro.app 2>/dev/null || true

echo "==> launching"
open -a /Applications/LaunchpadPro.app
sleep 2
if pgrep -fl "/Applications/LaunchpadPro.app" >/dev/null; then
    echo "==> running: $(stat -f '%Sm' /Applications/LaunchpadPro.app/Contents/MacOS/LaunchpadPro)"
else
    echo "==> WARNING: not running"
fi
