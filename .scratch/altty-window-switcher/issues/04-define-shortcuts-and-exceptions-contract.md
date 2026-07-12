Status: resolved
Type: grilling
Parent: ../map.md
Blocked by: 01

## Question

What exact settings and persistence contract should Altty expose for configurable shortcuts and the full AltTab-style Exceptions model, including bundle-identifier prefix matching, independent Hide and Ignore rules, title matching, fullscreen conditions, conflicts, defaults, editing flows, and malformed or missing applications?

## Answer

### Shortcut bindings

- All-Windows and Current-App each have exactly one configurable shortcut. Defaults are Option-Tab and Option-Grave.
- A binding consists of a main key and a non-empty combination of Option, Control and Command. Shift is reserved for reverse cycling and cannot be required by the base binding. Bare keys and multiple bindings per mode are unsupported.
- A Switcher Session remains active while any configured modifier is held and confirms when all configured modifiers are released.
- The two modes cannot share a binding. Settings atomically register both proposed bindings before replacing the old pair; any system or application registration conflict rejects the change, preserves both old bindings, and shows an unavailable-shortcut error.
- Altty does not take over or mutate macOS native shortcut settings.

### Exception identity and composition

- An Exception identifies applications by either an exact bundle ID or an explicitly selected bundle-ID prefix. App and running-process pickers create exact matches by default; prefix matching is an advanced option. Empty IDs are invalid.
- Hide and Ignore are independent positive restrictions and may both be enabled.
- Multiple matching Exceptions combine by union rather than list order: any Hide hides; Ignore uses the strongest match, with Always above When Fullscreen above None. Exact matches do not negate a matching prefix.
- Exception row order is presentation only. There are no reverse or allow-list rules.

### Hide and Ignore

- Hide is a Boolean. When enabled, every real window owned by a matching application is removed from both switcher modes. When disabled, the rule imposes no candidate filtering.
- Ignore is None, Always, or When Fullscreen. A match disables both global shortcuts while the matching application is frontmost; When Fullscreen additionally requires its current window to be fullscreen.
- Ignored shortcuts are actually disabled so the keystroke remains available to the foreground application or system; Altty must not consume the chord and merely no-op.
- Recompute Ignore when the frontmost application or its fullscreen state changes.
- Altty has no title matching and does not inspect titles for Exceptions. It also has no “when no open window” rule because windowless application placeholders are not candidates.

### Settings workflow

- Add an Exception from running applications, an application bundle picker, or advanced manual bundle-ID entry. Manual entry also chooses exact or prefix matching.
- Rows show resolved icon and name where available, bundle ID, matching type, and Hide/Ignore summary.
- A duplicate exact rule or identical prefix opens the existing rule. Exact and prefix rules may coexist.
- Missing, uninstalled or unresolvable applications retain their rules and display a generic icon plus bundle ID.
- Users may edit, delete and reorder rules. Ship with an empty Exception list; common remote-desktop or streaming applications may be suggested but are never enabled automatically.

### Persistence and lifecycle

- Store shortcuts and Exceptions locally in UserDefaults using versioned structured data and atomic validated replacement. No iCloud sync, cross-device sync, import or export in the first release.
- Isolate and report a malformed Exception without clearing valid peers. A malformed or unavailable shortcut falls back to defaults and shows a Settings warning. App updates use explicit schema migrations and never silently reset preferences.
- Without Accessibility trust, unregister both global shortcuts so Altty cannot consume unusable input; leave Menu Bar, Settings, permission explanation and the System Settings link available. Automatically attempt registration after trust returns and surface any new conflict.
- An active Switcher Session retains its original bindings and candidate snapshot. Shortcut changes register after it ends; Exception edits apply to the next session. Failed replacement continues using the complete old binding pair.
