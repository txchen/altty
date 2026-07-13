Status: resolved
Type: grilling
Parent: ../map.md
Blocked by: 01, 02, 03, 04, 05

## Question

What module boundaries, state model, event sources, concurrency model, private-API isolation strategy, persistence seams, and replacement plan for the current prototype should the Swift/AppKit implementation use to satisfy the settled behavior with low switching latency and testable failure modes?

## Comments

### 2026-07-13 — Validation dependency narrowed

The partial private-adapter validation now provides sufficient evidence to design an isolated, runtime-resolved and fail-closed SkyLight seam. Final Developer ID signing, notarization, cross-install TCC behavior and the remaining OS/hardware/Space matrix stay tracked by [Validate private adapter and permission lifecycle](08-validate-private-adapter-and-permission-lifecycle.md) as release gates rather than blocking architecture selection.

### 2026-07-13 — Target structure accepted

Use one AppKit executable target with explicit internal module and protocol boundaries. Do not split the first release into multiple Swift packages; preserve replaceability and testability through narrow interfaces inside the target.

### 2026-07-13 — Concurrency model accepted

Keep AppKit UI, Switcher Session coordination and observable application state on `@MainActor`. A `WindowInventory` actor serializes the long-lived window inventory and global MRU. SkyLight and Accessibility adapters convert callbacks into immutable events before submitting them to the inventory. Shortcut callbacks emit session commands rather than mutating UI or inventory directly. Window focus runs as an awaited transaction with postcondition verification before MRU promotion.

### 2026-07-13 — Inventory update policy and resource constraint

Build the initial WID-keyed inventory after Accessibility becomes available, then maintain it primarily from AX, workspace and private-adapter events. Reconcile on launch, wake, permission recovery, adapter restart and before a Switcher Session only when the inventory is dirty or event coverage is suspect. Do not run an unconditional five-second full scan. Coalesce event bursts, avoid polling while idle and perform expensive AX enrichment lazily for candidate windows. A Switcher Session freezes its ordered row snapshot; events may remove invalid windows but new or changed windows appear fully on the next session.

Altty must remain a lightweight background utility. Idle CPU wakeups, memory growth, AX calls and full inventory scans are explicit performance acceptance criteria rather than incidental implementation details.

### 2026-07-13 — SkyLight remains the primary focus path

Although multi-Space switching is not a user priority, retain the private adapter for reliable specific-WID focus. SkyLight is the default focus mechanism rather than a fallback: the focus transaction deminimizes through AX when needed, uses the private WID-targeted operation, performs any required AX raise/reacquisition, then verifies the focused PID and window before promoting MRU. Public app activation remains only a bounded failure fallback and is never treated as verified success by itself.

### 2026-07-13 — Current-Space inventory accepted

Use SkyLight as the authoritative discovery source but query and retain only the active Space. AX enriches those WIDs with semantic properties. Treat the current fullscreen Space as the active Space. When the user changes Spaces, replace the inventory with the newly active Space rather than tracking other Spaces in the background.

### 2026-07-13 — Internal module boundaries accepted

Keep one executable target organized into `Application`, `Input`, `WindowServer`, `Accessibility`, `Inventory`, `Switching`, `Exceptions`, `Persistence`, `Presentation` and `Diagnostics` areas. UI and input submit commands to Switching; Switching depends on Inventory and adapter protocols; concrete SkyLight/AX implementations sit at the edge and never depend back on UI. SkyLight declarations, function pointers and private types exist only inside WindowServer. Diagnostics expose adapter health and structured events without window titles.

### 2026-07-13 — Persistence boundary accepted

Persist one versioned, validated `SettingsSnapshot` as JSON under Application Support using temporary-file plus atomic replacement. Store shortcuts, Exceptions, launch behavior and UI preferences as one transaction; reject invalid changes without overwriting the last valid snapshot. Apply explicit sequential schema migrations. Preserve a corrupt input for diagnosis, load safe defaults and surface the recovery in Settings. Never persist MRU, inventory, AX elements, WIDs or adapter health. No app runtime setting requires Keychain.

### 2026-07-13 — Prototype replacement accepted

Delete the existing `Sources/Altty` prototype wholesale when implementation begins; do not preserve its types, behavior or source compatibility and do not build a migration layer. Rebuild the source tree against the accepted architecture. Retain `Package.swift`, `Resources/Info.plist` and packaging scripts only after reviewing each for continued relevance.

### 2026-07-13 — Lightweight resource budget accepted

Target under 0.2% average idle CPU over five minutes and under 50 MB idle resident memory. Never poll the window inventory on a fixed idle cadence. Coalesce event bursts over roughly 50–100 ms, avoid AX enrichment on the shortcut critical path, and target under 30 ms from a cached shortcut event to starting the focus transaction. Preserve the 100–150 ms panel presentation delay. Stress tests must demonstrate that inventory records, observers and AX references return to baseline after 1,000 window create/close cycles. Track CPU, memory, wakeups, AX calls, full reconciliations and switching latency; bound slow AX work off the main thread.

### 2026-07-13 — No public focus fallback

SkyLight is the sole focus mechanism. AX remains responsible for semantic enrichment and prerequisite operations such as deminimizing, but Altty never substitutes AX raise or application activation when private WID focus is unavailable or fails. If the startup capability check fails, leave switcher shortcuts unregistered and expose a clear unsupported state plus a user-triggered recheck. If a focus transaction fails verification, do not promote MRU; keep or restore the origin when possible and report failure.

### 2026-07-13 — Inventory identity model accepted

Key live records by WID and validate incremental events against PID plus the current inventory generation. Increment the generation whenever the active-Space inventory is rebuilt. Delete disappeared WIDs immediately; a later reused WID with a different PID or generation is a new window and inherits no MRU state. Do not retain timed tombstones. A Switcher Session owns immutable `WindowSnapshot` values rather than AX elements or mutable records; destruction may remove a candidate, while other mutations become visible next session.

### 2026-07-13 — Event authority accepted

Use SkyLight/WindowServer as authority for WID existence, create/destroy, focus and active-Space changes; `NSWorkspace` for application lifecycle, hidden state and frontmost application; AX observers for title, role, minimized state and other semantics. A verified Altty focus transaction emits the authoritative MRU promotion. Sleep/wake, display changes and permission recovery mark inventory dirty and may trigger a generation rebuild. Conflicts resolve by field ownership; uncertain values become stale rather than guessed or synchronously fetched on the shortcut path.

### 2026-07-13 — Test architecture accepted

Use pure unit tests for filtering, MRU, Exceptions, shortcut state, session snapshots, generations and settings migration. Deterministic adapter tests inject fake SkyLight, AX, workspace and clock events to cover closure races, WID reuse, timeouts, focus verification failure, permission revocation and event reordering. Real macOS smoke tests resolve symbols and enumerate test WIDs automatically, but focus-changing tests require explicit user initiation. Keep title-free event-trace fixtures for offline replay; production has no telemetry upload.

## Answer

Build Altty as one AppKit executable target with explicit internal boundaries rather than multiple Swift packages. Delete the disposable prototype source tree at implementation start and rebuild it; retain project metadata and packaging files only after review.

### Boundaries and dependencies

- `Application` owns startup, menu-bar lifecycle and dependency assembly.
- `Input` owns shortcut registration and the modifier/key interaction state machine.
- `WindowServer` is the only location containing SkyLight declarations, dynamic symbols, function pointers or private types.
- `Accessibility` owns AX observation, semantic attributes and prerequisite actions such as deminimizing.
- `Inventory` owns qualification, the active-Space WID inventory and global MRU.
- `Switching` owns Switcher Session snapshots, navigation and verified focus transactions.
- `Exceptions` owns exact/prefix bundle-ID matching plus independent Hide/Ignore policy.
- `Persistence` owns the versioned settings snapshot, validation and migrations.
- `Presentation` owns the switcher panel, Settings and menu-bar status.
- `Diagnostics` exposes local, title-free structured events and adapter health.

Dependencies point inward: Presentation and Input submit commands to Switching; Switching consumes Inventory and adapter protocols; concrete WindowServer/Accessibility implementations remain edge adapters and never depend on UI.

### State and concurrency

AppKit UI, Switcher Session coordination and observable app state remain on `@MainActor`. A `WindowInventory` actor serializes the live inventory and MRU. Adapters translate callbacks into immutable events before submitting them. Shortcut callbacks submit commands rather than mutating state. Focus is an awaited transaction, and only verified success promotes MRU.

Each live record is keyed by WID and checked against PID plus an inventory generation. A rebuild on Active Space change increments the generation. Removed WIDs disappear immediately; reused identifiers never inherit MRU. Sessions contain immutable `WindowSnapshot` rows, not AX elements or mutable records. Destruction can remove a live candidate, while other mutations appear next session.

### Discovery, enrichment and focus

SkyLight is authoritative for active-Space discovery, WID existence, create/destroy and focus events. Altty does not track inactive Spaces. AX enriches discovered WIDs with title, role and minimized state. `NSWorkspace` owns app lifecycle, hidden state and frontmost-app facts. Field ownership resolves conflicts; uncertain data becomes stale rather than guessed.

SkyLight is the sole specific-WID focus mechanism. AX may deminimize first but is never a focus fallback. Startup performs a read-only capability check; missing required behavior leaves switcher shortcuts unregistered and exposes an unsupported state with manual recheck. Failed focus does not promote MRU and keeps or restores the origin when possible. See [Use an isolated SkyLight adapter](../../../Docs/adr/0001-use-isolated-skylight-adapter.md).

### Updates and resource use

Build the initial inventory after Accessibility is available, then update primarily through events. Reconcile only on launch, wake, permission recovery, adapter restart or a dirty pre-session state. Coalesce bursts, perform expensive AX enrichment lazily and never poll on a fixed idle cadence.

Target under 0.2% average idle CPU over five minutes and under 50 MB idle resident memory. Target under 30 ms from a cached shortcut event to starting focus; preserve the 100–150 ms panel delay. Stress tests must show records, observers and AX references return to baseline after 1,000 window create/close cycles.

### Persistence and verification

Persist one versioned `SettingsSnapshot` JSON under Application Support using validated atomic replacement and sequential migrations. Corrupt input is retained for diagnosis while safe defaults load. MRU, inventory, WIDs, AX elements and adapter state never persist; no runtime setting uses Keychain.

Testing combines pure policy tests, deterministic fake-adapter/event-trace tests, and explicitly initiated macOS focus smoke tests. Diagnostics and fixtures exclude window titles; Altty uploads no telemetry.
