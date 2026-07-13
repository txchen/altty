# 16 — Configure shortcuts atomically

**What to build:** Let users configure exactly one shortcut for each switcher mode while preserving reliable session semantics. Invalid or conflicting edits leave the entire prior shortcut pair working, and unavailable/ignored shortcuts pass through rather than being consumed.

**Blocked by:** 15 — Add the Current-App Switcher

**Status:** ready-for-agent

- [ ] Shortcuts Settings presents one recorder for All-Windows and one for Current-App with current/default values and inline errors.
- [ ] A binding requires a main key and at least one of Option, Control or Command; Shift remains reserved for reverse navigation.
- [ ] Bare keys, Shift-required base bindings, duplicate mode bindings and multiple bindings per mode are rejected.
- [ ] A proposed pair is fully registered before the previous pair is removed; any registration failure preserves both prior bindings.
- [ ] System/application conflicts produce an unavailable-shortcut error without leaving a partial configuration.
- [ ] A Switcher Session remains active while any configured modifier is held and confirms only after all configured modifiers are released.
- [ ] Shortcut edits made during a session take effect only after that session ends.
- [ ] Missing Accessibility, failed SkyLight readiness and later Ignore policy can unregister/pass through chords without a silent no-op.
- [ ] Valid bindings persist through the versioned settings model and recover safely from malformed/unavailable persisted values.
- [ ] Deterministic tests cover validation, pairwise atomicity, conflicts, modifier-release semantics and session-time edits; real smoke tests cover registration and pass-through on supported keyboard layouts.
