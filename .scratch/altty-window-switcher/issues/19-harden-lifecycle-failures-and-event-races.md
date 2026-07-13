# 19 — Harden lifecycle, failures and event races

**What to build:** Make Altty remain deterministic and recoverable when applications, windows, permissions and system events change at hostile times. Failures never crash, falsely report success, corrupt MRU or leave an unusable shortcut captured.

**Blocked by:** 18 — Finish Settings, menu and presentation polish

**Status:** ready-for-agent

- [ ] Candidate closure during a session and target closure during confirmation finish or continue safely with correct selection and MRU.
- [ ] WID reuse, stale generation and mismatched PID events cannot mutate or inherit an unrelated record.
- [ ] Invalid/rebuilt AX elements, missing fields, `cannotComplete`, timeouts and hung/exiting applications are bounded off the main thread and represented as stale/unavailable state.
- [ ] SkyLight load/query/focus failure and false-success postconditions fail closed, leave MRU unchanged and expose recoverable diagnostics.
- [ ] Internal focus events and external user focus arriving out of order resolve without double promotion or promoting the wrong target.
- [ ] Accessibility revocation during idle, session and focus transaction unregisters shortcuts, releases observers and safely closes state; regrant rebuilds without restart.
- [ ] Shortcut/event-tap runtime failure stops consuming affected input and surfaces status.
- [ ] Active Space/display change during a session uses generation rules without mixing inventories or crashing the panel.
- [ ] Sleep/wake and adapter restart reconstruct observers/inventory without fixed polling or duplicated subscriptions.
- [ ] Missing, truncated, future-schema and interrupted-migration settings recover to safe defaults while preserving diagnosis and valid prior data where possible.
- [ ] Duplicate, lost and burst events trigger coalescing/reconciliation without linear work amplification.
- [ ] Replayable title-free event traces cover every race and assert no crash, false success, incorrect MRU, stuck session, captured unusable shortcut or private-content log.
