# Altty Architecture

Altty is intentionally small: it is a menu bar AppKit app with a title-list switcher. It uses an isolated, runtime-resolved SkyLight adapter for Active Space discovery and exact-window focus, and Accessibility for semantic enrichment and focus prerequisites. It does not use ScreenCaptureKit or Screen Recording permission.

## Modules

- `Application`: app lifecycle, production dependency assembly and effect execution.
- `Input`: replaceable shortcut registration, input events and mouse scroll reversal.
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
- The SkyLight notification stream supplies create, destroy, focus, visibility/geometry and Space-change triggers. Snapshot bursts use a fixed 75 ms coalescing window, one physical query and one merged follow-up. Ordinary events do not continually postpone or reject progress. Space replacement and monitoring epochs reject obsolete answers, even when an old OS call finishes after stop/restart. There is no inventory polling timer.
- AX title, role, subrole, minimized/fullscreen and transient facts are requested lazily for new or invalidated identities on bounded Dispatch workers. At most four query jobs run, at most one per PID; background jobs use at most three slots, reserving capacity for interactive focus work. An app-window enumeration is shared by a batch, traversal resumes across 250 ms elapsed-time slices, and each slice publishes completed patches before continuing. Individual IPC timeouts are capped by the remaining slice budget. Per-window semantic bursts use a fixed 75 ms window and permit only one outstanding enrichment, with one follow-up when facts changed during that read. Unknown or stale qualification facts fail closed.
- Session liveness uses the authoritative WID/PID/generation set, separately from the qualified candidate list. Temporary AX staleness cannot remove a captured live candidate or change its selection.
- A SkyLight focus notification for an undiscovered WID requests reconciliation and retains only the latest focus hint. An accepted snapshot validates its identity before replay; newer focus, destruction, Space changes, monitoring stop or absence from the snapshot discard obsolete hints.
- AX notification registration, window-ID reads in callbacks, and observer removal share a dedicated sleeping run loop with bounded messaging timeouts. Kernel liveness is checked both before and after asynchronous observer registration. Workspace retains notification-source identities when process identifiers disappear and rejects obsolete termination after PID reuse. Termination cancels queued AX work and removes that PID's observer; per-registration tokens reject queued callbacks after termination, PID reuse or monitoring restart. The main thread never waits for AX registration or cleanup.
- Workspace launch, termination, activation and hidden/unhidden notifications update only application-owned fields. Hidden-app and minimized real windows remain eligible.
- The first Active Space change notification immediately ends the Switcher Session and blocks new invocations against the old inventory, including invocations already awaiting a snapshot. Switching resumes after a current replacement is accepted and subscribed. Expensive discovery still coalesces; no old-Space fallback is provided during the transition.
- Active Space replacement increments the inventory generation and discards the prior records. Within a generation, events must match WID and PID, and a newly created/reused WID starts without prior metadata or MRU. Cold start keeps visible candidates in front-to-back order and defers minimized/hidden candidates with deterministic WID ordering.

## Interactive Switcher Sessions

- The configured All-Windows shortcut (Option-Tab by default) immediately snapshots the Active Space candidate order, invocation PID, shortcut description and temporary selection. Quick release begins verified exact-WID focus without presenting UI.
- The configured Current-App shortcut (Option-Grave by default) snapshots the frontmost PID before presentation and filters the same global MRU to that owner for the entire Current-App session.
- A session that remains active for 125 ms presents a compact vertical list. Repeated Tab and Shift-Tab, mouse hover and wheel update only the temporary selection; release or click confirms, while Escape, outside click and lost interaction context cancel.
- A session remains active while any configured Option, Control or Command modifier is held. Shortcut edits remain pending until that session ends, then atomically replace and persist the pair.
- Session rows remain stable under ordinary inventory changes and new windows. Destroyed candidates are removed, with selection advancing safely, and generation changes fail closed.
- A different mode shortcut cancels an unconfirmed session; once exact-WID confirmation begins, that transaction finishes before a later shortcut press can start a fresh session and snapshot. Modes never transition in place.
- Every confirmation has a monotonic transaction identity. Asynchronous deminimize, focus and postcondition callbacks must match it, so delayed results from a prior attempt cannot advance or fail a newer attempt for the same window identity.
- Panel updates preserve existing row views for selection-only changes, reload only changed content rows, and recompute size only for structural or presentation-preference changes. Selected actions continue to resolve by WindowIdentity.
- No thumbnails or live focus previews are supported by design.

## Mouse Scroll Reversal

- General settings schema v4 adds `reverseMouseWheel`, default off. Versions 1–3
  migrate with it disabled. Runtime changes occur only after successful persistence.
- The engine gates reversal on Accessibility independently of SkyLight and
  Exceptions. The adapter additionally preflights Input Monitoring, without
  prompting; only the explicit permission action requests access.
- `SystemMouseScrollAdapter` owns separate passive gesture and active scroll
  session taps on the main run loop. Disable, failed startup, permission loss,
  readiness recheck and application termination release both. Tap timeout
  attempts recovery; failed recovery reports an unavailable state.
- `ScrollInputClassifier` adapts Scroll Reverser's recent multi-touch (222 ms),
  ordinary-scroll timeout (333 ms) and momentum rules. Trackpad events pass
  through; mouse events reverse both axes in place, without posting events.
- All line, fixed-point and point deltas are captured before mutation, then
  written in that order. `MouseScrollHIDAccess` isolates runtime-resolved
  CoreGraphics/IOKit SPI to update the underlying HID axes for Safari and similar
  clients. Missing symbols leave reversal unavailable, without affecting switching.
- Apache-2.0 license and NOTICE accompany the source and packaged app. Synthetic
  event, classifier, engine, migration and presentation tests do not capture live
  input; physical mouse/trackpad validation remains a separate manual check.

## Persisted Shortcut Settings

- `ShortcutPair` contains exactly one base binding per switcher mode. Validation requires a main key and Option, Control or Command, reserves Shift for reverse navigation and rejects duplicate mode bindings.
- `SystemInputAdapter` registers forward and derived Shift-reverse chords under transaction-specific IDs. Every proposed chord is registered before superseded registrations are retired; any Carbon or monitor failure rolls back the proposal and leaves the prior pair intact.
- Settings are stored as a versioned JSON `SettingsSnapshot` under `Application Support/app.altty.macos/settings.json` using atomic file replacement. Malformed, unsupported or invalid input is preserved while safe defaults and an inline warning are presented.

## Ordered gestures, AX recovery and qualification

A read-only CG event tap on its own sleeping run loop records at most 128 registered
shortcut presses and their physical modifier releases. Carbon callbacks claim those
records on main; all logical shortcut events share one ordered task chain. Completed
gestures wait for a committed focus transaction to finish before starting another
session. Tap loss clears history and disables shortcuts; stale monitor callbacks are
rejected by generation. Ordinary typing is never retained.

AX enrichment retries only temporarily unavailable identities, at most three times
with 150/500/1000 ms backoffs. Backoff holds no query slot; successful patches publish
immediately. Process exit, observation stop and inventory invalidation cancel pending
work. Invalid elements and permanent errors do not retry. Unsupported optional
attributes are not transient failures.

SkyLight remains authoritative for window identity and Space membership. Additional
WindowServer layer/bounds metadata and AX main/fullscreen/parent facts filter empty
surfaces, child windows and non-main elevated windows. Floating/system-dialog
subroles are excluded; ordinary custom window subroles remain eligible. No per-app
blacklist or alternate focus path is introduced.

See [qa-fixtures.md](qa-fixtures.md) for pixel baselines, the real hostile app and
explicit physical validation boundaries.
