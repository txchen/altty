Label: wayfinder:map

## Destination

Produce an implementation-ready product and technical specification for Altty: an independently implemented Swift/AppKit macOS window switcher inspired by AltTab's mature behavior, scoped to the agreed list-only switching experience and ready for a later implementation phase.

The specification must settle user behavior, window discovery and focus semantics, configurable shortcuts, the full AltTab-style Exceptions model, UI, permissions, compatibility, testing, and signed/notarized direct plus Homebrew distribution.

## Notes

- Use `/grilling` and `/domain-modeling` for HITL decisions; ask one question at a time and update `CONTEXT.md` as terms settle.
- Use `/research` for AFK source and platform investigations; prefer the local reference repository at `/Users/hibiki/code/github/alt-tab-macos` and primary Apple documentation.
- Borrow behavior and architectural lessons from AltTab, but implement independently without copying its GPL source, assets, branding, or product identity.
- The selectable unit is a window. Option-Tab lists switchable windows across applications in MRU order; Option-Grave lists switchable windows of the current application.
- Default shortcuts are configurable. Exceptions include the full independent Hide and Ignore behaviors modeled after AltTab.
- The switcher is a list only: no screenshots, thumbnails, or preview capture.
- The app is an AppKit menu-bar app with no Dock icon. Minimum supported OS is macOS 15; support both Intel and Apple Silicon.
- Mac App Store distribution is out of scope. Releases must be Developer ID signed and notarized, available as a manual download and through Homebrew Cask.
- The first release has no in-app updater; Check for Updates may open the releases page.
- The existing code is a disposable validation prototype, not an architecture compatibility constraint.

## Decisions so far

<!-- Closed-ticket pointers are appended here. -->

- [Research AltTab window model](issues/01-research-alttab-window-model.md) — Use a cached WID inventory and global MRU split across isolated WindowServer/SkyLight and AX adapters; omit capture and windowless placeholders, and filter Current-App mode by invocation PID. Later architecture scope limits candidates to the active Space.
- [Research platform and distribution constraints](issues/02-research-platform-and-distribution-constraints.md) — Ship a non-sandboxed, hardened and notarized universal app via versioned ZIP and Homebrew Cask; gate AX/event-tap work on Accessibility, isolate SkyLight behind capability checks, and validate it under the final signed identity.
- [Define switcher interaction contract](issues/03-define-switcher-interaction-contract.md) — Use window-only stable sessions over one global MRU, immediate quick switching with delayed list display, non-focusing navigation, verified focus before MRU promotion, and explicit cancellation/failure behavior.
- [Define shortcuts and exceptions contract](issues/04-define-shortcuts-and-exceptions-contract.md) — Atomically manage one configurable binding per mode and app-identity Exceptions with independent Hide/Ignore restrictions, deterministic union semantics, empty defaults, and resilient local persistence.
- [Prototype list and settings experience](issues/05-prototype-list-and-settings-experience.md) — Use Variant A's compact centered list and native sidebar Settings, incorporating Variant B's management-first Exceptions pane; retain the full prototype only on its throwaway branch.
- [Choose technical architecture](issues/06-choose-technical-architecture.md) — Rebuild as one layered AppKit target with an actor-owned active-Space inventory, event-driven updates, SkyLight-only verified focus, atomic versioned settings and explicit lightweight performance budgets.

## Not yet specified

- Packaging automation, release hosting, Homebrew tap ownership, and operational release checklist depend on the distribution and architecture decisions.
- The exact implementation ticket breakdown belongs after the implementation-ready specification is complete.

## Out of scope

- Mac App Store submission and sandbox-driven compromises.
- Screenshots, thumbnails, live previews, and Screen Recording permission.
- Search and secondary window actions such as close, minimize, fullscreen, hide application, and quit application.
- Copying AltTab source code, assets, branding, or other GPL-covered implementation material.
- Legacy macOS support below macOS 15.
- Implementing the product during this wayfinding effort.
- In-app automatic updates in the first release.
- Discovering, listing or switching to windows on inactive Spaces.
