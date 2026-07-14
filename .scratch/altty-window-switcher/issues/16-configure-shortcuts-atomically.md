# 16 — Configure shortcuts atomically

**What to build:** Let users configure exactly one shortcut for each switcher mode while preserving reliable session semantics. Invalid or conflicting edits leave the entire prior shortcut pair working, and unavailable/ignored shortcuts pass through rather than being consumed.

**Blocked by:** 15 — Add the Current-App Switcher

**Status:** resolved

- [x] Shortcuts Settings presents one recorder for All-Windows and one for Current-App with current/default values and inline errors.
- [x] A binding requires a main key and at least one of Option, Control or Command; Shift remains reserved for reverse navigation.
- [x] Bare keys, Shift-required base bindings, duplicate mode bindings and multiple bindings per mode are rejected.
- [x] A proposed pair is fully registered before the previous pair is removed; any registration failure preserves both prior bindings.
- [x] System/application conflicts produce an unavailable-shortcut error without leaving a partial configuration.
- [x] A Switcher Session remains active while any configured modifier is held and confirms only after all configured modifiers are released.
- [x] Shortcut edits made during a session take effect only after that session ends.
- [x] Missing Accessibility, failed SkyLight readiness and later Ignore policy can unregister/pass through chords without a silent no-op.
- [x] Valid bindings persist through the versioned settings model and recover safely from malformed/unavailable persisted values.
- [x] Deterministic tests cover validation, pairwise atomicity, conflicts, modifier-release semantics and session-time edits; real smoke tests cover registration and pass-through on supported keyboard layouts.

## Answer

Implemented one validated recorder per switcher mode and a transaction-based Carbon registration layer that registers the complete proposed forward/reverse pair before retiring superseded IDs. Conflicts and monitor failures roll back the proposal, keep the prior pair active when one exists and otherwise leave the chords unregistered for pass-through. `SwitcherEngine` defers valid edits until the captured session ends, while modifier release is evaluated against every configured base modifier. Successful pairs persist as versioned, atomically replaced JSON; malformed, future-version and invalid settings recover to defaults with preserved input and inline warnings. Deterministic coverage exercises validation, registration order/rollback, pass-through, release semantics, session deferral and persistence, with an opt-in real Carbon registration smoke test documented in the README.
