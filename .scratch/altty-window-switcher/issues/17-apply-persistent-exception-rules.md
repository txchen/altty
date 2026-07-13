# 17 — Apply persistent Exception Rules

**What to build:** Give users persistent app-identity Exceptions that can hide matching windows and/or pass Altty shortcuts through to a frontmost application. Exact and prefix rules compose deterministically and are manageable from Settings without title-based behavior.

**Blocked by:** 16 — Configure shortcuts atomically

**Status:** ready-for-agent

- [ ] Users can add a rule from running applications, an application-bundle picker or advanced manual bundle-ID entry.
- [ ] Running-app and bundle pickers create exact rules by default; manual entry can explicitly select exact or prefix matching and rejects empty identifiers.
- [ ] Rows show resolved icon/name when available, bundle ID, match type and concise Hide/Ignore summary; missing applications remain editable with generic presentation.
- [ ] Duplicate exact or identical prefix identities edit the existing rule, while exact and prefix rules may coexist.
- [ ] Hide removes every matching real window from both modes without affecting shortcut availability.
- [ ] Ignore supports None, Always and When Fullscreen and causes both switcher shortcuts to pass through while its condition is active.
- [ ] Matching rules combine by union; strongest Ignore wins, exact does not negate prefix and row order has no policy effect.
- [ ] Ignore recomputes when frontmost application or fullscreen state changes and does not consume a disabled chord.
- [ ] There is no title matching, allow-list/negative rule or windowless-application condition; the default rule list is empty.
- [ ] Add/Edit/Delete/reorder uses validated atomic settings replacement; changes affect the next session and malformed peers cannot erase valid rules.
- [ ] Deterministic tests cover match/union/strength/filter/pass-through semantics and persistence; explicit smoke tests verify a chosen foreground application receives the configured chord.
