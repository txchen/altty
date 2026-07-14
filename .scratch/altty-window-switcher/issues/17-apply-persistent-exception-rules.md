# 17 — Apply persistent Exception Rules

**What to build:** Give users persistent app-identity Exceptions that can hide matching windows and/or pass Altty shortcuts through to a frontmost application. Exact and prefix rules compose deterministically and are manageable from Settings without title-based behavior.

**Blocked by:** 16 — Configure shortcuts atomically

**Status:** resolved

- [x] Users can add a rule from running applications, an application-bundle picker or advanced manual bundle-ID entry.
- [x] Running-app and bundle pickers create exact rules by default; manual entry can explicitly select exact or prefix matching and rejects empty identifiers.
- [x] Rows show resolved icon/name when available, bundle ID, match type and concise Hide/Ignore summary; missing applications remain editable with generic presentation.
- [x] Duplicate exact or identical prefix identities edit the existing rule, while exact and prefix rules may coexist.
- [x] Hide removes every matching real window from both modes without affecting shortcut availability.
- [x] Ignore supports None, Always and When Fullscreen and causes both switcher shortcuts to pass through while its condition is active.
- [x] Matching rules combine by union; strongest Ignore wins, exact does not negate prefix and row order has no policy effect.
- [x] Ignore recomputes when frontmost application or fullscreen state changes and does not consume a disabled chord.
- [x] There is no title matching, allow-list/negative rule or windowless-application condition; the default rule list is empty.
- [x] Add/Edit/Delete/reorder uses validated atomic settings replacement; changes affect the next session and malformed peers cannot erase valid rules.
- [x] Deterministic tests cover match/union/strength/filter/pass-through semantics and persistence; explicit smoke tests verify a chosen foreground application receives the configured chord.

## Answer

Implemented persistent exact/prefix Exception Rules with independent Hide and None/Always/When Fullscreen Ignore policy. `SwitcherEngine` filters both switcher modes at session capture, recomputes foreground pass-through from workspace and fullscreen changes, and applies rule edits only after an active session ends. Settings now supports running-app, application-bundle and manual creation plus resolved/missing rows, edit/delete/reorder and duplicate-identity replacement. Settings schema v2 migrates v1 shortcuts, saves complete snapshots atomically and decodes rules individually so malformed peers cannot erase valid entries. Deterministic coverage exercises matching, union/strength, filtering, foreground/fullscreen suppression, session deferral and persistence; the opt-in real input smoke verifies an ignored foreground probe receives both configured chords.
