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

## Current foundation

- Menu bar app
- Settings window
- Fail-closed readiness and recovery for Accessibility and SkyLight capability
- Event-driven, generation-safe Active Space window inventory with lazy AX enrichment
- Atomic configurable All-Windows and Current-App shortcut recorders with versioned local persistence
- Persistent exact/prefix Exception rules with independent Hide and foreground Ignore policy
- General, Shortcuts, management-first Exceptions and About settings destinations
- Replaceable system-adapter boundaries assembled around `SwitcherEngine`
- No thumbnails and no Screen Recording permission
