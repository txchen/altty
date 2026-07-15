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
- The app is an AppKit menu-bar app with no Dock icon. Minimum supported OS is macOS 15 and the only supported architecture is Apple silicon (`arm64`).
- Mac App Store distribution is out of scope. Releases must be Developer ID signed and notarized, available as a manual download and through Homebrew Cask.
- The first release has no in-app updater; Check for Updates may open the releases page.
- The existing code is a disposable validation prototype, not an architecture compatibility constraint.

## Decisions so far

<!-- Closed-ticket pointers are appended here. -->

- [Harden lifecycle, failures and event races](issues/19-harden-lifecycle-failures-and-event-races.md) — Correlate asynchronous focus work with monotonic transaction identities, reference-count failed-target suppression, fail readiness closed on Active Space query failure and bound AX window messaging; the deterministic suite covers the hostile lifecycle matrix.

- [Research AltTab window model](issues/01-research-alttab-window-model.md) — Use a cached WID inventory and global MRU split across isolated WindowServer/SkyLight and AX adapters; omit capture and windowless placeholders, and filter Current-App mode by invocation PID. Later architecture scope limits candidates to the active Space.
- [Research platform and distribution constraints](issues/02-research-platform-and-distribution-constraints.md) — Ship a non-sandboxed, hardened and notarized app via versioned ZIP and Homebrew Cask; gate AX/event-tap work on Accessibility, isolate SkyLight behind capability checks, and validate it under the final signed identity. Later release scope is arm64-only.
- [Define switcher interaction contract](issues/03-define-switcher-interaction-contract.md) — Use window-only stable sessions over one global MRU, immediate quick switching with delayed list display, non-focusing navigation, verified focus before MRU promotion, and explicit cancellation/failure behavior.
- [Define shortcuts and exceptions contract](issues/04-define-shortcuts-and-exceptions-contract.md) — Atomically manage one configurable binding per mode and app-identity Exceptions with independent Hide/Ignore restrictions, deterministic union semantics, empty defaults, and resilient local persistence.
- [Prototype list and settings experience](issues/05-prototype-list-and-settings-experience.md) — Use Variant A's compact centered list and native sidebar Settings, incorporating Variant B's management-first Exceptions pane; retain the full prototype only on its throwaway branch.
- [Choose technical architecture](issues/06-choose-technical-architecture.md) — Rebuild as one layered AppKit target with an actor-owned active-Space inventory, event-driven updates, SkyLight-only verified focus, atomic versioned settings and explicit lightweight performance budgets.
- [Define release and update contract](issues/07-define-release-and-update-contract.md) — Publish immutable signed/notarized arm64 ZIPs with permanent bundle ID `app.altty.macos` through approval-gated GitHub Releases, update a project-owned Homebrew tap, and provide only manual browser-based update checks in v1.
- [Define acceptance and regression coverage](issues/09-define-acceptance-and-regression-coverage.md) — Gate behavior with deterministic policy/race tests, explicit macOS focus/TCC smoke tests, measurable lightweight performance budgets, tested-only OS support and build-SHA-linked signed RC verification.
- [Switch immediately with the All-Windows shortcut](issues/13-switch-immediately-with-all-windows-shortcut.md) — Quick Option-Tab snapshots cached Active-Space MRU candidates, confirms through verified SkyLight WID focus without panel flash, promotes only after the exact PID/WID postcondition, and is covered by a real-AppKit focus smoke that restores the origin through the same product path.
- [Add the Current-App Switcher](issues/15-add-current-app-switcher.md) — Register Option-Grave alongside Option-Tab and run both modes through the shared session engine, with Current-App filtering the global MRU by an invocation-snapshotted frontmost PID and deterministic cross-mode interruption.
- [Configure shortcuts atomically](issues/16-configure-shortcuts-atomically.md) — Provide one validated binding per mode, atomically replace the full Carbon registration pair with rollback on conflicts, defer edits across active sessions, and persist versioned shortcut settings with safe recovery.
- [Build reproducible arm64 release automation](issues/21-build-reproducible-arm64-release-automation.md) — Share deterministic arm64 package inspection between secret-free dry runs and an approval-gated Developer ID/notarization workflow, publish immutable build-SHA-linked ZIP metadata, and update the project Homebrew tap through a lifecycle-tested Cask PR.

## Not yet specified

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
- Intel Macs and `x86_64` or universal release artifacts.
