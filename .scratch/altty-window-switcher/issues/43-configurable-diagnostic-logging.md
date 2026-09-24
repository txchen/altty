# 43 — configurable diagnostic logging

Status: resolved

## Behavior

General → Diagnostics → Enable diagnostic logging controls detailed shortcut,
performance and successful readiness messages. It defaults off for both fresh
installs and existing version-four settings missing the optional field. Error
messages remain enabled. The preference is persisted atomically and applied
after successful saving, without restarting; startup restores it before adapters
start. Mouse-menu toggles and login-item reconciliation preserve the setting.

A thread-safe shared gate covers the passive keyboard thread and main-thread
adapters. Disabled shortcut logging skips message construction as well as the
system logging call. No ordinary typed text or window titles are recorded.

## Validation

147 tests pass, including legacy settings loading, disk round trip, disabled
message evaluation and the real Settings checkbox action. All 36 visual fixtures
pass after inspecting the new Diagnostics card and updating the eight affected
General/permission-recovery baselines. Build 2026092308 includes this setting.
The app and ZIP in `dist/` pass release verification. The existing authorized
2026092307 process (PID 56015) remains running; no restart or permission reset was
performed for this settings change. Reopen the packaged app to use the new setting.

During this work the user also asked about AltTab's visible item count. Local
v11.7.1 uses screen-relative layout capped at 80% screen height, not a fixed seven
items. No change to Altty's seven-row default was requested or made.
