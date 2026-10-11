# Hint Mode progress and decision trail

## Todo
- [x] Read poteto-mode Principles
- [x] 1. `how` over affected subsystems (subagent report, summarized below)
- [x] 2. architect: reduced. One sketch (this file + scaffold commit) instead of an arena. Reason: Shortcat/Neru precedent and the grounding report fix the shape; the one structural fork (engine-owned session vs separate controller) is decided below with rationale.
- [x] 3. Throughput checkpoint (below)
- [ ] 4. Delegate W1 (Hints runtime) and W2 (settings/engine/UI/hotkey) in separate worktrees; review diffs
- [ ] 5. Merge, wire production, full test run, app build
- [ ] 6. Real-surface verification (blocked while the screen is locked; smoke harness prepared)
- [ ] 7. interrogate: only if design is contested
- [ ] 8. Opening a PR: skip unless asked; local commits on a branch

## Throughput checkpoint
- Blocking first steps: scaffold commit with `HintModeSettings`, `HintShortcutAdapter`, `HintSessionController`. Both workers compile against it.
- Independent workstreams: W1 writes only new files under `Sources/Altty/Hints/` plus new tests. W2 edits Persistence, Switching, Input, Presentation, Application and existing tests.
- Shared mutable state: `AppEnvironment.swift`/`AppDelegate.swift` belong to W2 only; W1 exposes `SystemHintSessionController` and `CarbonHintShortcutAdapter` which I wire after merge. Separate git worktrees so neither build sees the other's intermediate state.
- Smallest safe decomposition: two workers. Splitting W1 further (scanner/overlay/tap) would share the controller and the target model, so it stays one owner.

## Decisions
- Hint session runtime lives outside `SwitcherEngine`. The engine only owns settings and decides the desired Hint Shortcut registration (`.setHintShortcut(ShortcutBinding?)`, declarative, idempotent). Reason: the session has no interaction with Switcher Sessions, inventory or SkyLight; putting it in a 1055-line engine would add state with no shared invariants.
- Desired registration = enabled && shortcut != nil && accessibility == .available && exception verdict != false. Not gated by SkyLight.
- `GeneralSettings.hintMode` is a required init parameter so every hand-built `GeneralSettings(...)` site must pass it through (prevents silent reset).
- Hint shortcut: key + at least one of ⌃⌥⌘, Shift allowed, must not equal any switcher chord or its Shift-reverse chord. Separate Carbon handler signature so pair transactions are untouched.
- Keys typed while the scan runs are buffered and replayed (Shortcat buffers Enter).
- Screen locked during this run: AX returns application-role references for every window, hit-test fails. Docs/qa-fixtures.md recorded the same symptom; it may be the lock, not the OS. Real-surface checks wait for an unlocked session.
