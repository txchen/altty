# 15 — Add the Current-App Switcher

**What to build:** Add the default Option-Grave Current-App Switcher with the same quick and held interaction as All-Windows, filtered to windows owned by the application that was frontmost when the session began.

**Blocked by:** 14 — Complete the interactive All-Windows Switcher Session

**Status:** resolved

- [x] Altty registers Option-Grave when ready and invokes Current-App mode without interfering with All-Windows state.
- [x] Invocation snapshots the frontmost PID before Altty's panel can affect application activation.
- [x] Candidates filter the single global MRU to the invocation PID; Current-App does not maintain a second MRU.
- [x] Quick tap, delayed panel, forward/reverse wrap, modifier confirmation, mouse behavior and cancellation match All-Windows behavior.
- [x] Multiple windows from the same application appear as separate rows and exact-WID focus selects the chosen window.
- [x] Empty, sole-current and sole-different candidate behavior matches the common session contract.
- [x] A frontmost-application change after invocation does not change the session's owner filter.
- [x] Rapid alternating input between the two modes ends or starts sessions deterministically without mixing snapshots.
- [x] Deterministic tests prove PID snapshot/filter/order and cross-mode interruption behavior; an explicit macOS smoke test switches among several same-app windows.

## Answer

Implemented the Current-App Switcher as a mode of the shared `SwitcherEngine` session pipeline. Option-Grave and Shift-Option-Grave filter the single global MRU by the invocation-snapshotted frontmost PID, preserve window-level rows and exact-WID focus, and cancel an unconfirmed different-mode session before a later press starts a fresh snapshot. Deterministic coverage includes filtering/order, windowless and transient invocation owners, shared MRU promotion, common quick/held behavior and cross-mode races; opt-in macOS smoke coverage exercises both Option-Tab and repeated Option-Grave focus across same-app windows.
