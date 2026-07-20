# LaunchpadPro

LaunchpadPro is a native macOS app launcher built with SwiftUI and AppKit. It gives you a fast full-screen grid for opening apps, organizing folders, searching, and keeping multiple saved layouts.

## Highlights

- Full-screen paged app grid
- Fast app search
- Drag-and-drop app ordering
- Folder creation, renaming, scrolling, and drag-out behavior
- Trackpad-friendly page swiping with damped motion
- Native five-finger pinch-to-open gesture
- Menu bar launcher with optional visibility
- Global hotkey and hot corner support
- Up to 3 saved layout memories
- Local-only data storage
- Universal macOS build for Apple Silicon and Intel Macs

## Download

Download `LaunchpadPro.dmg` from the GitHub Releases page, open it, then drag `LaunchpadPro.app` into `Applications`.

## Requirements

- macOS 26 or later
- Xcode 26 or later for local builds

## Usage

- Open launcher: five-finger pinch, `Option + Space`, menu bar icon, hot corner, or `launchpadpro://show`
- Multi-display launch: the full-screen panel opens on the display containing the mouse pointer; pinching again while it is visible moves it to the newly targeted display
- Search: type immediately after opening
- Open app: click an app icon
- Reorder: drag an app to a new position
- Create folder: drag one app onto another app
- Rename folder: open a folder and click its title
- Save layouts: Settings -> Advanced -> Layout Memory
- Close launcher: `Esc` or click outside

## Build

```bash
cd /Users/leo/本地/Project_Git/LaunchpadPro
./bundle.sh
```

The app bundle is created at:

```text
build/LaunchpadPro.app
```

`bundle.sh` builds a universal binary:

```text
arm64 + x86_64
```

## Build DMG

```bash
./dmg.sh
```

The disk image is created at:

```text
build/LaunchpadPro.dmg
```

If you have a Developer ID certificate installed, pass it with `SIGN_IDENTITY`:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./dmg.sh
```

Without `SIGN_IDENTITY`, the app is ad-hoc signed for local testing.

## Maintainer Release

For Developer ID signing with Xcode automatic signing:

```bash
./xcode-release.sh
```

This archives a universal macOS app through `LaunchpadPro.xcodeproj`, exports it with Developer ID signing, and creates:

```text
build/LaunchpadPro.dmg
```

To submit the archive for Apple notarization through Xcode's logged-in developer account:

```bash
UPLOAD_FOR_NOTARIZATION=1 ./xcode-release.sh
```

After Apple finishes processing the archive:

```bash
USE_NOTARIZED_APP=1 ./xcode-release.sh
```

## Local Data

- Layout, folders, custom names, hidden apps, and layout memories:

```text
~/Library/Application Support/LaunchpadPro/layout.json
```

- Settings are stored in `UserDefaults`.

## Project Structure

- `AppDelegate.swift`: app lifecycle, menu bar, hotkey, hot corners, login item, URL scheme
- `OverlayController.swift`: full-screen overlay window and trackpad paging input
- `FiveFingerPinchMonitor.swift`: global five-finger pinch recognition
- `LaunchModel.swift`: app list, folders, layout persistence, layout memories
- `LauncherViews.swift`: root launcher UI, search bar, app icons, vertical mode folder overlay
- `PagedLauncherView.swift`: paged grid, drag ordering, folder interactions
- `SettingsView.swift`: settings window
- `AppScanner.swift`: app discovery and icon lookup
- `AppDirectoryWatcher.swift`: automatic refresh when app directories change
- `bundle.sh`: universal app bundle builder
- `dmg.sh`: DMG builder
- `xcode-release.sh`: Xcode automatic signing and Developer ID release builder
- `deploy.sh`: local install and restart helper

## Five-Finger Gesture

macOS does not provide a public API for observing a specific finger count globally.
LaunchpadPro therefore keeps all access to Apple's private `MultitouchSupport`
framework inside `FiveFingerPinchMonitor.swift`. The recognizer only opens the
launcher after a five-touch cloud contracts substantially without moving its
centroid, which avoids treating five-finger swipes as pinches. While the feature
The raw callback remains observational and always returns `0`; macOS 26 does not
reliably support suppressing Spotlight Apps through that return value. LaunchpadPro
instead preserves and temporarily disables the system four/five-finger pinch
preferences while it owns the gesture, restoring them when the feature is turned
off. A frame-time gap also resets the one-shot recognizer, so devices that omit a
zero-contact release frame can still begin the next gesture. The launcher triggers
after roughly 10% touch-cloud contraction over two consecutive frames, so a short,
natural five-finger pinch is sufficient without bringing every finger to the center.
The launcher opens with an 80 ms panel fade and a restrained 100 ms content reveal
to avoid a lingering layered-opacity effect.

This implementation is intended for direct distribution and local use, not the Mac
App Store. A future macOS update may require updating the private-framework bridge.
The architecture was informed by the actively maintained, MIT-licensed
[MiddleDrag](https://github.com/NullPointerDepressiveDisorder/MiddleDrag) project
and [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport).

## License

MIT
