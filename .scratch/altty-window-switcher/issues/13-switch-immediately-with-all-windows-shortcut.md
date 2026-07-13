# 13 — Switch immediately with the All-Windows shortcut

**What to build:** Make a quick default Option-Tab press switch immediately to the next Switchable Window in global MRU without showing a panel. The selected WID is focused through SkyLight, verified, and promoted only after success.

**Blocked by:** 12 — Maintain the Active Space WindowInventory

**Status:** ready-for-agent

- [ ] When ready, Altty registers the default Option-Tab invocation without mutating native macOS shortcut settings.
- [ ] Invocation snapshots cached Active-Space candidates and chooses the item after the currently focused window in global MRU order, wrapping when required.
- [ ] If the current window is absent, forward selection chooses the first candidate.
- [ ] No candidates and a sole current-window candidate perform no action; one different candidate focuses directly.
- [ ] Releasing Option before panel delay confirms the selected target rather than cancelling silently.
- [ ] Confirmation deminimizes through Accessibility when necessary, performs specific-WID SkyLight focus and verifies the target PID/window postcondition.
- [ ] Only verified success promotes the target in MRU; failure preserves or restores the origin when possible and leaves MRU unchanged.
- [ ] Failure closes the interaction and produces a short nonblocking user-visible error without attempting public AX/application focus fallback.
- [ ] Deterministic tests cover selection, wrap, empty/single cases, minimized prerequisites, success, false success, target closure and MRU invariants.
- [ ] An explicitly invoked macOS smoke test demonstrates quick switching among multiple windows, including two windows owned by the same application.
