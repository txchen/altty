# 19 — Harden lifecycle, failures and event races

**What to build:** Make Altty remain deterministic and recoverable when applications, windows, permissions and system events change at hostile times. Failures never crash, falsely report success, corrupt MRU or leave an unusable shortcut captured.

**Blocked by:** 18 — Finish Settings, menu and presentation polish

**Status:** resolved

- [x] Candidate closure during a session and target closure during confirmation finish or continue safely with correct selection and MRU.
- [x] WID reuse, stale generation and mismatched PID events cannot mutate or inherit an unrelated record.
- [x] Invalid/rebuilt AX elements, missing fields, `cannotComplete`, timeouts and hung/exiting applications are bounded off the main thread and represented as stale/unavailable state.
- [x] SkyLight load/query/focus failure and false-success postconditions fail closed, leave MRU unchanged and expose recoverable diagnostics.
- [x] Internal focus events and external user focus arriving out of order resolve without double promotion or promoting the wrong target.
- [x] Accessibility revocation during idle, session and focus transaction unregisters shortcuts, releases observers and safely closes state; regrant rebuilds without restart.
- [x] Shortcut/event-tap runtime failure stops consuming affected input and surfaces status.
- [x] Active Space/display change during a session uses generation rules without mixing inventories or crashing the panel.
- [x] Sleep/wake and adapter restart reconstruct observers/inventory without fixed polling or duplicated subscriptions.
- [x] Missing, truncated, future-schema and interrupted-migration settings recover to safe defaults while preserving diagnosis and valid prior data where possible.
- [x] Duplicate, lost and burst events trigger coalescing/reconciliation without linear work amplification.
- [x] Replayable title-free event traces cover every race and assert no crash, false success, incorrect MRU, stuck session, captured unusable shortcut or private-content log.

## Answer

Lifecycle hardening is implemented at the established engine, inventory and adapter seams. The deterministic suite covers candidate and target closure, WID/PID/generation rejection, AX stale/unavailable fields, verified focus and MRU behavior, readiness revocation/regrant, shortcut cleanup, Active Space replacement, wake reconstruction, settings recovery and burst coalescing.

The remaining same-target callback race is closed with a monotonic focus-transaction identity. Production deminimize, focus and verification callbacks are accepted only by the transaction that launched them, and overlapping failed-focus suppression is reference-counted so an older recovery cannot expose a newer failed target to external focus promotion. Active Space query failure now transitions WindowServer readiness to unavailable instead of retaining stale state, and individual AX window calls use the bounded messaging timeout already applied to application queries.

`Tests/Fixtures/LifecycleRaceTraces.md` catalogs the title-free replay matrix and its safety invariant for every hostile lifecycle category. The new same-target trace replays target destruction, same-identity reconstruction, a new confirmation and a late failure from the prior transaction; it then completes the newer transaction and asserts no false failure, incorrect MRU or stuck session. A diagnostic privacy trace proves injected window content cannot enter the closed diagnostic event stream. The full deterministic suite passes with 88 tests.
