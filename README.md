# Altty

Altty is a native Apple-silicon menu-bar window switcher for macOS 15 and later.

## Install

Requires an Apple Silicon Mac running macOS 15 or later.

```sh
brew install --cask txchen/tap/altty
open /Applications/Altty.app
```

Grant Accessibility permission when Altty asks. Mouse wheel reversal also needs
Input Monitoring. Screen Recording permission is not required.

Quit Altty before updating:

```sh
brew update
brew upgrade --cask altty
```

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
For stable local signing, save the full name of an installed code-signing identity
(Apple Development or Developer ID Application) as one line in
`.altty-signing-identity`. This ignored, machine-local file applies only to the
development bundle; `ALTTY_SIGNING_IDENTITY` overrides it. A configured identity
that cannot sign causes the build to fail instead of falling back to ad-hoc signing.
Without either setting, builds use ad-hoc signing. Keep the bundle identifier,
signing identity, and launch path stable to help macOS retain privacy permissions
across builds. Switching from ad-hoc signing may require granting permissions once
again. Local builds do not need notarization.

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

## Publish a release

Pushes to `master` and pull requests run tests, scan Git history for credentials,
and build an ad-hoc-signed package without Apple credentials.

Push a `MAJOR.MINOR.PATCH` tag after CI passes:

```sh
git tag 0.1.0
git push origin 0.1.0
```

The Release workflow reruns CI, imports the Developer ID Application certificate
into a temporary keychain, builds, and submits the ZIP to Apple. After Apple
accepts it, the workflow staples the ticket, verifies the final ZIP, tests Homebrew
installation and removal, and publishes the GitHub Release. A failed or timed-out
notarization does not publish a release. The workflow saves the package and
submission receipt as Actions artifacts for 14 days.

Set these secrets in the `production-release` GitHub environment:

- `DEVELOPER_ID_APPLICATION_P12_BASE64`: base64-encoded certificate and private key.
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`: the export password.
- `APPLE_DEVELOPER_ID_NAME`: the organization name on the certificate.
- `APPLE_TEAM_ID`: the Apple team identifier.
- `APPLE_ID`: the Apple Account email address.
- `APPLE_APP_SPECIFIC_PASSWORD`: an app-specific password for notarization.

The public [Homebrew tap](https://github.com/txchen/homebrew-tap) checks for new
stable releases twice an hour. Its Update Altty workflow verifies the downloaded
package and tests installation before committing the new Cask. Later releases
also test upgrading from the previous Cask. Run that workflow manually to update
the tap immediately after publication. Each repository uses its own GitHub token;
the tap needs no Apple credentials or cross-repository write token.

## Optional hardware checks

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
