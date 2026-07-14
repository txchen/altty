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
3. Shortcuts remain disabled until both dependencies report ready.
4. Readiness starts the event-driven inventory: SkyLight replaces or reconciles the Active Space WID set, AX lazily enriches requested identities off-main, and Workspace owns application lifecycle/visibility facts.
5. Adapter callbacks become immutable inventory events. `WindowInventory` validates WID, PID and generation before updating actor-isolated records, and `SwitcherEngine` remains the observable test seam.
6. AppKit Presentation renders immutable engine state in the menu and Settings shell.

## Readiness Lifecycle

- Launch checks Accessibility trust and dynamically resolves the complete required SkyLight symbol set before performing a read-only managed-Space/window query and verifying per-window event subscription. A later subscription failure transitions readiness to unsupported and fails closed.
- Shortcuts remain unregistered until both gates are ready. Wake and explicit user rechecks fail closed before repeating both checks; ordinary application activity rechecks only Accessibility trust.
- Accessibility prompting is reachable only through the user's Grant Accessibility action. Trust changes are observed from application/workspace activity plus a one-second observation window for up to two minutes after an explicit request or while System Settings remains active; no permission timer runs during ordinary idle use.
- Runtime trust revocation ends the active Switcher Session boundary, unregisters shortcuts and releases AX observers.
- Losing readiness also stops inventory observation and clears live WIDs/MRU. Recovery creates a fresh generation; neither WIDs nor MRU are persisted.
- SkyLight failure exposes no public focus fallback. Readiness diagnostics contain only fixed permission/capability categories.

## Active Space Inventory

- `CGSCopyManagedDisplaySpaces` contributes only each display's `Current Space`, including a currently presented fullscreen Space. `CGSCopyWindowsWithOptionsAndTags` supplies the authoritative front-to-back WIDs for those Spaces, including invisible/minimized candidates.
- The SkyLight notification stream supplies create, destroy, focus, visibility/geometry and Space-change triggers. Snapshot bursts coalesce into one read-only reconciliation, stale query results are sequence-rejected, and there is no inventory polling timer.
- AX title, role, subrole, minimized/fullscreen and transient facts are requested lazily for new or invalidated identities on detached work with a bounded AX messaging timeout. Per-window semantic bursts debounce and permit only one outstanding enrichment, with one follow-up when facts changed during that read. Unknown or stale qualification facts fail closed.
- Workspace launch, termination, activation and hidden/unhidden notifications update only application-owned fields. Hidden-app and minimized real windows remain eligible.
- Active Space replacement increments the inventory generation and discards the prior records. Within a generation, events must match WID and PID, and a newly created/reused WID starts without prior metadata or MRU. Cold start keeps visible candidates in front-to-back order and defers minimized/hidden candidates with deterministic WID ordering.

## Current Constraints

- Shortcut registration and concrete switching sessions arrive in later implementation tickets; tickets 11–12 establish their fail-closed lifecycle and inventory boundaries.
- No thumbnails are supported by design.
