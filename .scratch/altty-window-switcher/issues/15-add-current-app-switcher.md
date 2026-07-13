# 15 — Add the Current-App Switcher

**What to build:** Add the default Option-Grave Current-App Switcher with the same quick and held interaction as All-Windows, filtered to windows owned by the application that was frontmost when the session began.

**Blocked by:** 14 — Complete the interactive All-Windows Switcher Session

**Status:** ready-for-agent

- [ ] Altty registers Option-Grave when ready and invokes Current-App mode without interfering with All-Windows state.
- [ ] Invocation snapshots the frontmost PID before Altty's panel can affect application activation.
- [ ] Candidates filter the single global MRU to the invocation PID; Current-App does not maintain a second MRU.
- [ ] Quick tap, delayed panel, forward/reverse wrap, modifier confirmation, mouse behavior and cancellation match All-Windows behavior.
- [ ] Multiple windows from the same application appear as separate rows and exact-WID focus selects the chosen window.
- [ ] Empty, sole-current and sole-different candidate behavior matches the common session contract.
- [ ] A frontmost-application change after invocation does not change the session's owner filter.
- [ ] Rapid alternating input between the two modes ends or starts sessions deterministically without mixing snapshots.
- [ ] Deterministic tests prove PID snapshot/filter/order and cross-mode interruption behavior; an explicit macOS smoke test switches among several same-app windows.
