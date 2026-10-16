# UI and Accessibility regression fixtures

Run `ALTTY_SWIFT_BUILD_SYSTEM=native scripts/test.sh` for deterministic coverage.
The native backend is an optional local workaround; omit the variable where the
standard Swift build backend works.

## Rendered UI baselines

Install Pillow for the Python interpreter used by the script, then run
`scripts/check-visuals.sh --check`. It renders the production switcher and settings
views with synthetic content in light/dark appearances at 1x/2x: short lists,
CJK/long titles, scrolled selection, removed rows, General and Exceptions.

Baselines live under `Tests/Fixtures/VisualBaselines/macos-<major>`. Each directory
records the exact OS build. Missing baselines fail; `--record` explicitly replaces
them and requires visual review. The comparator rejects missing/extra images,
dimension changes and more than 0.1% changed pixels (channel difference > 8).
It writes comparison.json and diff PNGs under `.build/visual-qa/current`.

These are deterministic content-view captures, not screenshots of the compositor.
Icons use a fixed symbol, vibrancy is inactive, and the native source-list selection
highlight is excluded because AppKit cacheDisplay renders that system effect black.
Altty's own switcher selection remains captured. Window shadows, live wallpaper
blending and actual display scaling require manual QA. Current baselines are from
macOS 27.0 build 26A428; other major versions need separately reviewed baselines.

## Real hostile application

`scripts/check-hostile-fixture.sh` builds a disposable AppKit app and an AX client
using the production adapter. The app opens two windows, stalls its main thread for
900 ms, creates/closes 20 more windows, then closes everything and exits. The client
starts enrichment during the stall and requires real window semantics to recover
within the production retry budget. The script separately checks 22 creates and
22 closes. All sources are under Tests/Fixtures and are excluded from app packaging.

Exit 77 means the AX client lacks Accessibility permission; it never prompts or
changes permissions. Other AX failures return a failing exit code even if lifecycle
validation passes. Reports are under `.build/qa`; only synthetic fixture data is logged.
The standalone fixture also accepts window count, churn count (up to 1,000), stall
milliseconds and lifetime; see its usage output.

On the current macOS 27.0 build 26A428 host, lifecycle validation passed, but AX
recovery did not: AXWindows returned two application-role references and window-ID
lookup returned illegalArgument (-25201). The same malformed references occurred
before a stall and in an independent minimal Objective-C AppKit app/client with no
Altty code. This isolates the failure from Altty's retry changes but does not prove
its OS-level cause. Keep this integration gate failing until a usable system run
passes; simulated retry tests are not a substitute.

## Physical acceptance still required

Exercise quick complete shortcut taps during a main-thread stall, held-modifier
navigation, input permission revocation, monitor restart, Space transitions and
representative apps (dialogs, floating palettes, slide shows). The gesture observer
is read-only and retains only a bounded history of registered chords; if the system
cannot install it, shortcuts report Input Monitoring unavailable. No typed text is
recorded. Resource and long-running acceptance remains in [performance.md](performance.md).

## Exact-window focus regression

Run `ALTTY_SWIFT_BUILD_SYSTEM=native scripts/check-window-focus.sh` before delivering
changes to switching. This starts two disposable AppKit apps with three windows
each, uses the production WindowFocusExecutor, checks exact PID/WID for 24 forward/
reverse transitions, and minimizes/restores one window in each app. It restores the
previous foreground window afterward and terminates its own fixtures. It changes
focus during the run, logs only fixture identities/timings, and never synthesizes
shortcut key presses. Exit 77 means the client lacks Accessibility permission.

On 2026-09-23 this caught the original missing-AXRaise bug: SkyLight returned success
but the second window never became focused. The corrected mandatory-SkyLight then
AX-ordering sequence passed all 24 transitions and both restorations on this host.
Physical hotkey delivery and third-party app compatibility remain separate checks.

Update 2026-09-23: the unmodified hostile AX recovery check now passes on this same
host, along with 22 creates/closes. The earlier malformed-reference observation is
historical, not an ongoing failing gate; its environmental cause was not established.

Settings visual coverage also includes Shortcuts, About and the mouse Input
Monitoring recovery state, bringing the fixture total to 36 PNGs. Permission dialogs
remain a user-driven QA gate; the visual fixture does not grant or request access.

## Altty-owned window focus

Run `ALTTY_SWIFT_BUILD_SYSTEM=native scripts/check-self-window-focus.sh` to check
the local AppKit path with two disposable windows. It checks 20 exact focus
sequences and four minimized restorations, then restores the previously focused
window. Before the local-PID scheduler fix, the same production AXRaise call
terminated the probe with SIGTRAP. This check is separate from remote-app focus.

## Shortcuts becoming unresponsive

`ALTTY_SWIFT_BUILD_SYSTEM=native scripts/test.sh --filter SwitcherReentrancyTests`
holds inventory responses across focus completion, confirmation, navigation and
session replacement. The pre-fix engine resurrects a completed `verifying`
session, blocking subsequent shortcuts indefinitely.

For diagnostic capture, first enable General → Diagnostics → Enable diagnostic
logging (off by default). For physical QA, mix quick Option-Tab taps, held Tab navigation, Shift-only
backward steps and Option-Grave while windows open/close. Both modes must remain
responsive after release. On recurrence, preserve the process and inspect Unified
Log subsystem `app.altty.macos`, category `Shortcut`: `physical_press`,
`carbon_press`, `queued`, `handling`, `wait`, `wait_resumed`, `invoked`, `end`.
These stages contain no window titles or ordinary typed input. A passing actor
race regression does not prove all global-input failure modes are resolved.

## Mouse Mode HUD and settings

Run `ALTTY_SWIFT_BUILD_SYSTEM=native scripts/check-mouse-visuals.sh` to render
production AppKit views into `.build/mouse-visuals/current`. The fixture adds
slow, normal, fast, scanning, and label-entry HUD states in light and dark
appearance at 1x and 2x. It also renders the existing 36 switcher and settings
scenarios. It does not change accepted baselines or user settings.

Inspect General and Shortcuts for the new controls. The General pane scrolls
to the permissions and diagnostics cards below Mouse Mode. Compare the
unchanged switcher, Exceptions, and About images with their accepted baselines.
HUD snapshots prove layout only. They do not prove hardware key delivery,
fullscreen visibility, display transitions, or permission and lock behavior.
