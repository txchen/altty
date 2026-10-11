# Altty

Altty is a native Apple-silicon menu-bar window switcher for macOS 15 and later.

## Build

```sh
scripts/build-app.sh
scripts/test.sh
```

The app bundle is created at:

```text
.build/Altty.app
```

The build script produces an arm64 development application with the distinct
`app.altty.macos.dev` identity at `.build/Altty.app`.
`scripts/test.sh` runs the public `SwitcherEngine` tests on both Command Line
Tools-only and full-Xcode installations.

If a newer toolchain's default Swift build backend fails to initialize, use
`ALTTY_SWIFT_BUILD_SYSTEM=native scripts/test.sh` and
`ALTTY_SWIFT_BUILD_SYSTEM=native scripts/build-app.sh`. The runner also supplies the
Swift Testing interop-library search path used by current Command Line Tools.

Run `ruby scripts/test-release-contract.rb` for secret-free Cask URL, workflow
filename, first-tap-publication and metadata-only-upgrade regression checks.
These use temporary Git repositories and do not install or uninstall applications.

## Release dry run

Release packaging can be exercised without Apple or GitHub credentials:

```sh
scripts/package-release.sh 1.2.3 42
```

This creates `Altty-1.2.3-arm64.zip`, `checksums.txt`, and
`release-metadata.json` under `.build/artifacts`. The package is rejected unless
it is arm64-only, targets macOS 15, uses `app.altty.macos`, carries the supplied
versions, has hardened runtime enabled, contains no forbidden entitlements, and
passes strict signature and content inspection. Delete the output directory
before deliberately rebuilding the same version; release artifacts are never
overwritten.

Pushing a `MAJOR.MINOR.PATCH` tag runs the approval-gated `production-release`
job. That job imports a Developer ID Application certificate into an ephemeral
keychain, notarizes and staples the app, rebuilds and re-verifies the final ZIP,
then publishes the immutable GitHub Release and opens a project tap Cask PR.
The repository environment must supply the Apple credentials documented by the
workflow plus `HOMEBREW_TAP_TOKEN` and `HOMEBREW_TAP_REPOSITORY`.

The normal test run never changes focus. Explicitly exercise the real,
read-only SkyLight capability check after a macOS update with:

```sh
ALTTY_RUN_SKYLIGHT_SMOKE=1 scripts/test.sh --filter realReadOnlySkyLightCapabilityCheck
```

The inventory smoke test is also read-only. Launch a controlled fixture app,
record the WIDs it expects on the currently presented Space, then run:

```sh
ALTTY_RUN_INVENTORY_SMOKE=1 \
ALTTY_INVENTORY_FIXTURE_PID=<pid> \
ALTTY_INVENTORY_FIXTURE_WIDS=<wid,wid> \
ALTTY_INVENTORY_INACTIVE_FIXTURE_WIDS=<wid,wid> \
scripts/test.sh --filter realReadOnlyActiveSpaceInventoryMatchesControlledFixture
```

The inactive-WID variable is optional, but supplying it verifies that windows
the fixture placed on a non-presented Space are absent from the snapshot.

The All-Windows focus smoke test changes focus. Launch a controlled fixture
application with at least two windows on the Active Space, list the frontmost
origin WID first, and explicitly run:

```sh
ALTTY_RUN_FOCUS_SMOKE=1 \
ALTTY_FOCUS_FIXTURE_PID=<pid> \
ALTTY_FOCUS_FIXTURE_WIDS=<origin-wid,target-wid> \
scripts/test.sh --filter realImmediateAllWindowsShortcutFocusesTheNextWindow
```

The script builds a dedicated AppKit probe with a real application event loop.
Success requires Altty to receive the registered shortcut, verify the target
PID/WID and MRU promotion, then switch back and verify restoration of the origin.
A visible focus change without those engine postconditions is not a passing smoke.

The Current-App focus smoke test changes focus. Launch a controlled fixture
application with at least three windows on the Active Space, list the frontmost
origin WID first, and explicitly run:

```sh
ALTTY_RUN_CURRENT_APP_FOCUS_SMOKE=1 \
ALTTY_FOCUS_FIXTURE_PID=<pid> \
ALTTY_FOCUS_FIXTURE_WIDS=<origin-wid,target-wid,other-wid> \
scripts/test.sh --filter realCurrentAppShortcutSwitchesAmongWindowsOwnedByFrontmostApplication
```

The smoke test sends Option-Grave twice while Option remains held, verifies
that the third WID is promoted in the shared MRU, and restores the fixture's
origin window before exiting. Both focus smoke tests restore their origin WID.

Exception pass-through smoke testing changes no macOS shortcut preferences, but
it does temporarily claim the configured chords. It installs an Ignore Always
rule for a foreground probe app, verifies the engine unregisters both shortcuts,
then requires the probe to receive physical Option-Tab and Option-Grave presses.
It also proves a second real Carbon registrar can claim the same chords. Focus
the probe window and press both chords when prompted.
Run it on each supported keyboard layout when Option-Tab and Option-Grave are
free:

```sh
ALTTY_RUN_SHORTCUT_SMOKE=1 \
scripts/test.sh --filter realIgnoredForegroundApplicationReceivesConfiguredShortcutPair
```

## Mouse wheel direction

In Settings → General, enable **Reverse mouse wheel direction** to reverse mouse
scrolling on both axes, independently of the window switcher. The single toggle
is off by default and persists across restarts. Set your preferred trackpad
direction in macOS System Settings; Altty does not change that preference.

This feature requires Accessibility and Input Monitoring. If General shows a
permission warning, use the permission button, enable Altty in System Settings,
then choose Check Readiness (or restart Altty if macOS requests it).

Quit Scroll Reverser or disable other mouse-direction tools before testing to
avoid double reversal. Check a long page in Safari and a Finder window: the
mouse should reverse, while two-finger trackpad scrolling and its momentum
should remain unchanged. Also check horizontal scrolling, turning the toggle
off, and restarting Altty with it on.

Mouse/trackpad identification and the HID compatibility path are adapted from
[Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser/tree/187bf3945b6107cd8486327c6165f32e523535a4),
under Apache-2.0. This uses upstream touch-timing heuristics, not guaranteed
per-device identification; third-party drivers and unusual gesture settings
still need hardware validation. License and attribution ship in the app's
`Contents/Resources/ThirdParty/ScrollReverser` directory.

## Keyboard hints

Hint Mode labels clickable elements so they can be clicked from the keyboard.
It is off by default. Turn on **Enable keyboard hints** in Settings → General,
then record a shortcut for **Show hints** in Settings → Shortcuts. No shortcut
is registered until both are set. Hint Mode needs only Accessibility.

Press the shortcut to label the frontmost window, its sheets and popovers and
its menu bar items. With a menu open, only that menu is labelled. Type a label
to select an element, then:

| Key | Action |
|---|---|
| Return | Default action (press buttons and menu items, otherwise click) |
| Return twice | Double click |
| ⌃ Return | Right click |
| ⌘ / ⇧ / ⌥ Return | Click with those modifiers |
| Tap ⌃ | Move the pointer onto the element |
| Escape, the shortcut again | Cancel |

Typing another label moves the selection; Delete removes a typed letter, then
the selection. The pointer is not moved back after a click.

Electron apps get `AXManualAccessibility` and Chromium browsers get a temporary
`AXEnhancedUserInterface` the first time they are hinted, because both build
their web-content tree only for assistive tools. Test those apps with a freshly
launched process: tools such as Shortcat leave the attribute set.

Scan a running app with the production scanner without showing any UI:

```sh
ALTTY_RUN_HINT_SCAN_SMOKE=1 ALTTY_HINT_SCAN_PID=<pid> \
scripts/test.sh --filter HintScanSmoke
```

## Current foundation

- Menu bar app
- Settings window
- Optional mouse-only scroll reversal with trackpad gesture discrimination
- Optional keyboard hints for clicking elements of the frontmost window
- Fail-closed readiness and recovery for Accessibility and SkyLight capability
- Event-driven, generation-safe Active Space window inventory with lazy AX enrichment
- Atomic configurable All-Windows and Current-App shortcut recorders with versioned local persistence
- Persistent exact/prefix Exception rules with independent Hide and foreground Ignore policy
- General, Shortcuts, management-first Exceptions and About settings destinations
- Replaceable system-adapter boundaries assembled around `SwitcherEngine`
- No thumbnails and no Screen Recording permission

## Default exceptions

Fresh settings include fullscreen shortcut pass-through for Screen Sharing,
Microsoft Remote Desktop / Windows App, TeamViewer, VirtualBox, Parallels,
Citrix Viewer (both bundle IDs), Amazon DCV, VMware Fusion and UTM. These apps'
windows remain visible in Altty; only their foreground fullscreen sessions receive
shortcuts directly. Parallels uses the `com.parallels.` prefix; other entries use
exact bundle identifiers. McAfee's Safari helper windows are hidden.

The recommendations follow [AltTab v11.7.1's default exceptions](https://github.com/lwouis/alt-tab-macos/blob/v11.7.1/src/preferences/Preferences.swift).
Altty does not need AltTab's windowless-Finder rule because it only lists real windows.
All entries can be edited or deleted in Settings → Exceptions. Saved lists, including
an intentionally empty list and lists migrated from older versions, are preserved.
These defaults are also used by the existing safe-defaults recovery path when a
settings file cannot be loaded; the original invalid file is preserved for diagnosis.
