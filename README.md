# LaunchpadPro

LaunchpadPro is a native macOS app launcher built with SwiftUI and AppKit. It gives you a fast full-screen grid for opening apps, organizing folders, searching, and keeping multiple saved layouts.

## Highlights

- Full-screen paged app grid
- Fast app search
- Drag-and-drop app ordering
- Folder creation, renaming, scrolling, and drag-out behavior
- Trackpad-friendly page swiping with damped motion
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

- Open launcher: `Option + Space`, menu bar icon, hot corner, or `launchpadpro://show`
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

## License

MIT
