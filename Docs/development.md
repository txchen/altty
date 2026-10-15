# Develop and release Altty

Run these commands from the repository root.

## Build locally

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

