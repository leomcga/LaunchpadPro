## LaunchpadPro 1.2.2

LaunchpadPro 1.2.2 keeps the gesture configuration healthy on its own: the
suppression of the macOS 26 Spotlight Apps pinch now repairs itself when
anything else on the system disturbs it.

### Highlights

- Automatic repair of the gesture override: LaunchpadPro re-checks the system
  gesture switches after every wake from sleep and every 5 minutes, fixing
  drift caused by older builds, System Settings rewrites, or an interrupted
  Dock restart; a check is silent unless a value actually drifted
- The five-finger pinch no longer opens the macOS 26 Spotlight Apps search
  alongside the launcher: the system response is suppressed through the Dock's
  `showLaunchpadGestureEnabled` switch, which macOS 26 actually consults
- The system five-finger spread-to-show-desktop gesture works again; earlier
  builds zeroed the shared trackpad pinch/spread recognizer keys, which macOS
  26 pairs with the "Show Desktop" gesture
- Upgraded installs automatically restore trackpad keys zeroed by earlier
  builds; disabling the pinch setting restores the Dock switch to its previous
  value

### Install

Download `LaunchpadPro.dmg`, open it, and drag `LaunchpadPro.app` into `Applications`.

This release is signed with a Developer ID certificate and notarized by Apple,
so it can be opened normally after installation.
