# 14 — Complete the interactive All-Windows Switcher Session

**What to build:** Extend All-Windows switching into the complete held-shortcut list experience. A user can inspect a stable compact list, navigate in both directions with keyboard or mouse, confirm by releasing modifiers or clicking, and cancel without changing focus.

**Blocked by:** 13 — Switch immediately with the All-Windows shortcut

**Status:** ready-for-agent

- [ ] The compact panel appears only when a session remains active for approximately 100–150 ms; quick taps never flash it.
- [ ] A session freezes mode, invocation PID, ordered `WindowSnapshot` rows and temporary selection while allowing destroyed candidates to be removed.
- [ ] Repeated Tab cycles forward, Shift-Tab cycles backward and both directions wrap.
- [ ] Releasing all configured modifiers confirms exactly one focus transaction.
- [ ] Escape, outside click, lost interaction context and abnormal shortcut interruption cancel, close the panel and preserve focus/MRU.
- [ ] Hover changes the shared temporary selection, click confirms immediately and mouse wheel cycles with wraparound.
- [ ] Navigation never focuses or previews a candidate; the invoking window remains frontmost until confirmation.
- [ ] New windows and ordinary attribute changes do not insert or reorder rows mid-session; a destroyed selected row advances safely.
- [ ] The panel shows mode/shortcut, application icon, title, application name and relevant minimized/hidden/fullscreen state in a compact vertical list with accessible selection.
- [ ] Deterministic engine tests cover timing, stable snapshots, all navigation/cancellation paths and candidate invalidation; AppKit tests verify visible behavior without asserting private view hierarchy.
