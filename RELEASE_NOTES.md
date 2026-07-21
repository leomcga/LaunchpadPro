## LaunchpadPro 1.2.1

LaunchpadPro 1.2.1 fixes the five-finger pinch racing the macOS 26 Spotlight
Apps window and restores the system spread-to-show-desktop gesture.

### Fixes

- The five-finger pinch no longer opens the macOS 26 Spotlight Apps search
  alongside the launcher: the system response is now suppressed through the
  Dock's `showLaunchpadGestureEnabled` switch, which macOS 26 actually consults
- The system five-finger spread-to-show-desktop gesture works again; earlier
  builds zeroed the shared trackpad pinch/spread recognizer keys, which macOS 26
  pairs with the "Show Desktop" gesture
- Upgraded installs automatically repair trackpad keys zeroed by earlier builds;
  disabling the pinch setting restores the Dock switch to its previous value

### Install

Download `LaunchpadPro.dmg`, open it, and drag `LaunchpadPro.app` into `Applications`.

This release is signed with a Developer ID certificate and notarized by Apple,
so it can be opened normally after installation.
