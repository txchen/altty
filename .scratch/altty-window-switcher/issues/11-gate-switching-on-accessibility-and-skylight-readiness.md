# 11 — Gate switching on Accessibility and SkyLight readiness

**What to build:** Give users a complete readiness and recovery flow for Accessibility trust and required SkyLight capability. Altty remains useful enough to explain and repair missing access, but never registers or consumes switcher shortcuts until both gates are ready.

**Blocked by:** 10 — Rebuild the production App shell

**Status:** ready-for-agent

- [ ] General Settings and the menu-bar menu distinguish Accessibility missing, SkyLight unsupported and ready states with concise recovery actions.
- [ ] The Accessibility system prompt is triggered only by an explicit user action; denial never causes repeated automatic prompting.
- [ ] Granting or regranting Accessibility is detected without restarting the application and transitions readiness correctly.
- [ ] Runtime revocation ends any active session, unregisters switcher shortcuts and releases Accessibility observers.
- [ ] The WindowServer adapter dynamically resolves required SkyLight symbols and performs a read-only capability query without changing focus.
- [ ] A failed capability check leaves shortcuts unregistered, reports an unsupported state and retries only on startup, wake or a user-requested recheck.
- [ ] No public focus fallback is exposed when SkyLight is unavailable.
- [ ] Diagnostics record permission and capability categories without window titles or user content.
- [ ] Deterministic engine tests cover grant, denial, retry, revocation, unavailable SkyLight and recovery transitions; an explicitly invoked smoke test exercises the real read-only capability check.
