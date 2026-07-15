# Altty Architecture

Altty is intentionally small: it is a menu bar AppKit app with a title-list switcher. It uses an isolated, runtime-resolved SkyLight adapter for Active Space discovery and exact-window focus, and Accessibility for semantic enrichment and focus prerequisites. It does not use ScreenCaptureKit or Screen Recording permission.

## Modules

- `Application`: app lifecycle, production dependency assembly and effect execution.
- `Input`: replaceable shortcut registration and input events.
- `WindowServer`: the only home for SkyLight declarations and private types.
- `Accessibility`: trust state, semantic enrichment and focus prerequisites.
- `Inventory`: the actor-isolated Active Space inventory and global MRU.
- `Switching`: the value-based `SwitcherEngine` command/event/state/effect seam.
- `Exceptions`, `Persistence`, `Presentation` and `Diagnostics`: replaceable policy and edge adapters.

## Runtime Flow

1. `AppDelegate` assembles the production adapters and sends `.launch` to `SwitcherEngine`.
2. The engine requests Accessibility and WindowServer capability checks as effects.
3. Shortcuts remain unregistered until both dependencies report ready. The configured pair is then registered as one transaction; a conflict leaves the complete previous pair active.
4. Readiness starts the event-driven inventory: SkyLight replaces or reconciles the Active Space WID set, AX lazily enriches requested identities off-main, and Workspace owns application lifecycle/visibility facts.
5. Adapter callbacks become immutable inventory events. `WindowInventory` validates WID, PID and generation before updating actor-isolated records, and `SwitcherEngine` remains the observable test seam.
6. AppKit Presentation renders immutable engine state in the menu, Settings shell and non-activating switcher panel.

## Readiness Lifecycle

- Launch checks Accessibility trust and dynamically resolves the complete required SkyLight symbol set before performing a read-only managed-Space/window query and verifying per-window event subscription. A later subscription failure transitions readiness to unsupported and fails closed.
- Shortcuts remain unregistered until both gates are ready. Wake and explicit user rechecks fail closed before repeating both checks; ordinary application activity rechecks only Accessibility trust.
- Accessibility prompting is reachable only through the user's Grant Accessibility action. Trust changes are observed from application/workspace activity plus a one-second observation window for up to two minutes after an explicit request or while System Settings remains active; no permission timer runs during ordinary idle use.
- Runtime trust revocation ends the active Switcher Session boundary, unregisters shortcuts and releases AX observers.
- Any readiness, monitoring or future Ignore-policy disablement unregisters the Carbon bindings, so unavailable shortcuts pass through instead of being consumed by a no-op.
- Losing readiness also stops inventory observation and clears live WIDs/MRU. Recovery creates a fresh generation; neither WIDs nor MRU are persisted.
- SkyLight failure exposes no public focus fallback. Readiness diagnostics contain only fixed permission/capability categories.

## Active Space Inventory

- `CGSCopyManagedDisplaySpaces` contributes only each display's `Current Space`, including a currently presented fullscreen Space. `CGSCopyWindowsWithOptionsAndTags` supplies the authoritative front-to-back WIDs for those Spaces, including invisible/minimized candidates.
- The SkyLight notification stream supplies create, destroy, focus, visibility/geometry and Space-change triggers. Snapshot bursts coalesce into one read-only reconciliation, stale query results are sequence-rejected, and there is no inventory polling timer.
- AX title, role, subrole, minimized/fullscreen and transient facts are requested lazily for new or invalidated identities on detached work with a bounded AX messaging timeout. Per-window semantic bursts debounce and permit only one outstanding enrichment, with one follow-up when facts changed during that read. Unknown or stale qualification facts fail closed.
- Workspace launch, termination, activation and hidden/unhidden notifications update only application-owned fields. Hidden-app and minimized real windows remain eligible.
- Active Space replacement increments the inventory generation and discards the prior records. Within a generation, events must match WID and PID, and a newly created/reused WID starts without prior metadata or MRU. Cold start keeps visible candidates in front-to-back order and defers minimized/hidden candidates with deterministic WID ordering.

## Interactive Switcher Sessions

- The configured All-Windows shortcut (Option-Tab by default) immediately snapshots the Active Space candidate order, invocation PID, shortcut description and temporary selection. Quick release begins verified exact-WID focus without presenting UI.
- The configured Current-App shortcut (Option-Grave by default) snapshots the frontmost PID before presentation and filters the same global MRU to that owner for the entire Current-App session.
- A session that remains active for 125 ms presents a compact vertical list. Repeated Tab and Shift-Tab, mouse hover and wheel update only the temporary selection; release or click confirms, while Escape, outside click and lost interaction context cancel.
- A session remains active while any configured Option, Control or Command modifier is held. Shortcut edits remain pending until that session ends, then atomically replace and persist the pair.
- Session rows remain stable under ordinary inventory changes and new windows. Destroyed candidates are removed, with selection advancing safely, and generation changes fail closed.
- A different mode shortcut cancels an unconfirmed session; once exact-WID confirmation begins, that transaction finishes before a later shortcut press can start a fresh session and snapshot. Modes never transition in place.
- Every confirmation has a monotonic transaction identity. Asynchronous deminimize, focus and postcondition callbacks must match it, so delayed results from a prior attempt cannot advance or fail a newer attempt for the same window identity.
- No thumbnails or live focus previews are supported by design.

## Shortcut Settings

- `ShortcutPair` contains exactly one base binding per switcher mode. Validation requires a main key and Option, Control or Command, reserves Shift for reverse navigation and rejects duplicate mode bindings.
- `SystemInputAdapter` registers forward and derived Shift-reverse chords under transaction-specific IDs. Every proposed chord is registered before superseded registrations are retired; any Carbon or monitor failure rolls back the proposal and leaves the prior pair intact.
- Settings are stored as a versioned JSON `SettingsSnapshot` under `Application Support/app.altty.macos/settings.json` using atomic file replacement. Malformed, unsupported or invalid input is preserved while safe defaults and an inline warning are presented.
