# 12 — Maintain the Active Space WindowInventory

**What to build:** Maintain a lightweight, event-driven inventory of Switchable Windows on the Active Space. The inventory combines authoritative WIDs with Accessibility semantics and application state, provides deterministic cold-start MRU ordering and replaces itself safely when the Active Space changes.

**Blocked by:** 11 — Gate switching on Accessibility and SkyLight readiness

**Status:** ready-for-agent

- [ ] SkyLight provides the authoritative WID set for the Active Space, including the currently presented fullscreen Space and excluding inactive Spaces.
- [ ] Accessibility enriches candidate WIDs with title, role, minimized state and other required semantics without blocking the main thread.
- [ ] Workspace events supply application lifecycle, hidden state and frontmost-application facts.
- [ ] Generic qualification rejects non-window/transient elements conservatively while retaining real minimized and hidden-app windows.
- [ ] Live records are keyed by WID and validated by PID plus inventory generation; reused WIDs cannot inherit prior MRU.
- [ ] Active Space changes increment generation and replace the inventory rather than retaining inactive-Space windows.
- [ ] Cold start seeds MRU from WindowServer front-to-back order with deterministic tie-breaking; MRU/WIDs are not persisted across launches.
- [ ] Create, destroy, focus, app lifecycle and semantic events update the inventory through immutable events, with field conflicts resolved by authority.
- [ ] Expensive AX enrichment is lazy, event bursts are coalesced and the idle implementation performs no fixed-cadence polling.
- [ ] Deterministic tests cover qualification, cold-start order, create/destroy, WID reuse, stale fields, generation replacement and exclusion of inactive Spaces; a read-only macOS smoke test compares observed windows with a controlled fixture application.
