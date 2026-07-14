# 18 — Finish Settings, menu and presentation polish

**What to build:** Complete the production-facing Altty experience around the working switchers: polished compact list placement, full Settings content, menu-bar status, launch behavior and manual update/support information.

**Blocked by:** 17 — Apply persistent Exception Rules

**Status:** resolved

- [x] The compact list uses native translucent styling, full-row accent selection and legible primary/secondary/state text without copying AltTab branding or layout.
- [x] Long titles/application names truncate to one line; icons and badges remain aligned; roughly six to eight rows show before vertical overflow and selection stays visible.
- [x] Invocation centers the panel on the pointer's display, falling back to the invoking window's display and then the primary display, and never spans displays.
- [x] General Settings includes Accessibility/readiness action, launch at login and supported list-presentation basics.
- [x] Shortcuts and Exceptions panes present every behavior from their completed slices with inline validation/recovery.
- [x] About presents product/version information, project/support links and Check for Updates.
- [x] Check for Updates opens the latest GitHub Releases page in the default browser and performs no background version or network request.
- [x] The menu-bar menu shows readiness/permission status, Settings, Accessibility action, Check for Updates and Quit without candidate or Exception management duplication.
- [x] Permission, compatibility and corrupt-settings warnings appear inline rather than as modal launch blockers.
- [x] The versioned JSON `SettingsSnapshot` is saved atomically under Application Support with sequential migration and corrupt-file preservation; runtime inventory/MRU state is never persisted.
- [x] UI accessibility, keyboard focus, multi-display placement, overflow, launch-at-login and browser actions have behavior-level tests.

## Answer

Finished the production-facing shell around both switchers. The panel now captures persisted six-to-eight-row density preferences, keeps native full-row selection and one-line aligned content, and chooses the pointer, invoking-window or primary display in order while clamping its frame to that display. Settings now has complete General, Shortcuts, Exceptions and About panes with keyboard focus, inline readiness/recovery, Service Management launch-at-login, product/build details and explicit project/support/update actions. The menu exposes only readiness and top-level app actions; Check for Updates uses a narrow explicit action that opens the latest GitHub Releases page without background networking.

`SettingsSnapshot` schema v3 adds General settings, migrates v1 through v2 sequentially, validates complete snapshots, writes atomically and preserves distinct invalid inputs in diagnostic copies while never encoding inventory or MRU state. Deterministic coverage now includes migration/corruption, launch-item success/failure/approval/rollback, Settings focus and accessibility, menu behavior, exact browser destinations, text/overflow accessibility, and pointer/invoking/primary multi-display placement. `./scripts/test.sh` passes all 86 tests, and `./scripts/build-app.sh` produces a verified arm64 `app.altty.macos` menu-bar app.
