# 12 — Maintain the Active Space WindowInventory

**What to build:** Maintain a lightweight, event-driven inventory of Switchable Windows on the Active Space. The inventory combines authoritative WIDs with Accessibility semantics and application state, provides deterministic cold-start MRU ordering and replaces itself safely when the Active Space changes.

**Blocked by:** 11 — Gate switching on Accessibility and SkyLight readiness

**Status:** resolved

- [x] SkyLight provides the authoritative WID set for the Active Space, including the currently presented fullscreen Space and excluding inactive Spaces.
- [x] Accessibility enriches candidate WIDs with title, role, minimized state and other required semantics without blocking the main thread.
- [x] Workspace events supply application lifecycle, hidden state and frontmost-application facts.
- [x] Generic qualification rejects non-window/transient elements conservatively while retaining real minimized and hidden-app windows.
- [x] Live records are keyed by WID and validated by PID plus inventory generation; reused WIDs cannot inherit prior MRU.
- [x] Active Space changes increment generation and replace the inventory rather than retaining inactive-Space windows.
- [x] Cold start seeds MRU from WindowServer front-to-back order with deterministic tie-breaking; MRU/WIDs are not persisted across launches.
- [x] Create, destroy, focus, app lifecycle and semantic events update the inventory through immutable events, with field conflicts resolved by authority.
- [x] Expensive AX enrichment is lazy, event bursts are coalesced and the idle implementation performs no fixed-cadence polling.
- [x] Deterministic tests cover qualification, cold-start order, create/destroy, WID reuse, stale fields, generation replacement and exclusion of inactive Spaces; a read-only macOS smoke test compares observed windows with a controlled fixture application.
