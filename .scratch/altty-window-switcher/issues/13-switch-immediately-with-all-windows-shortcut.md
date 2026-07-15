# 13 — Switch immediately with the All-Windows shortcut

**What to build:** Make a quick default Option-Tab press switch immediately to the next Switchable Window in global MRU without showing a panel. The selected WID is focused through SkyLight, verified, and promoted only after success.

**Blocked by:** 12 — Maintain the Active Space WindowInventory

**Status:** resolved

- [x] When ready, Altty registers the default Option-Tab invocation without mutating native macOS shortcut settings.
- [x] Invocation snapshots cached Active-Space candidates and chooses the item after the currently focused window in global MRU order, wrapping when required.
- [x] If the current window is absent, forward selection chooses the first candidate.
- [x] No candidates and a sole current-window candidate perform no action; one different candidate focuses directly.
- [x] Releasing Option before panel delay confirms the selected target rather than cancelling silently.
- [x] Confirmation deminimizes through Accessibility when necessary, performs specific-WID SkyLight focus and verifies the target PID/window postcondition.
- [x] Only verified success promotes the target in MRU; failure preserves or restores the origin when possible and leaves MRU unchanged.
- [x] Failure closes the interaction and produces a short nonblocking user-visible error without attempting public AX/application focus fallback.
- [x] Deterministic tests cover selection, wrap, empty/single cases, minimized prerequisites, success, false success, target closure and MRU invariants.
- [x] An explicitly invoked macOS smoke test demonstrates quick switching among multiple windows, including two windows owned by the same application.

## Answer

Implemented immediate All-Windows switching through the shared session engine with cached Active-Space MRU selection, delayed-panel quick confirmation, minimized-window preparation, exact SkyLight WID focus, Accessibility postcondition verification, success-only MRU promotion and fail-closed recovery.

The original in-process smoke host could post Option-Tab but did not dispatch Carbon hot-key callbacks, allowing macOS-native focus movement to look like partial success. The smoke now launches a dedicated AppKit probe with a real application event loop and the production `AppDelegate`. It requires the registered shortcut event to drive the engine, verifies target PID/WID focus and MRU promotion, then switches through Altty again and verifies restoration of the origin. The All-Windows smoke passed against two windows of one fixture application; the shared Current-App three-window smoke also passed. `scripts/test.sh` passes all 86 deterministic tests across 11 suites.
