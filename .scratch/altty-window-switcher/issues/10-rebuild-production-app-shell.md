# 10 — Rebuild the production App shell

**What to build:** Replace the disposable prototype with the production macOS 15, arm64 menu-bar application foundation. A user can launch Altty, see its readiness status, open the four-pane Settings shell and quit it. The implementation establishes `SwitcherEngine` as the primary behavior seam and assembles replaceable system adapters without carrying prototype compatibility forward.

**Blocked by:** None — can start immediately

**Status:** resolved

- [x] The disposable production source is removed rather than incrementally adapted, while still-relevant product metadata and packaging inputs are reviewed and retained deliberately.
- [x] The application builds and launches natively on Apple silicon with macOS 15 as its minimum deployment target and `app.altty.macos` as the production bundle ID.
- [x] Altty runs as a menu-bar application with no Dock icon and provides readiness, Settings and Quit actions.
- [x] Settings opens a native sidebar window with General, Shortcuts, Exceptions and About destinations, even if later-ticket controls are initially unavailable.
- [x] Application startup assembles Input, WindowServer, Accessibility, Inventory, Switching, Exceptions, Persistence, Presentation and Diagnostics boundaries without private types crossing into core state.
- [x] `SwitcherEngine` accepts commands/events/state and exposes immutable presentation state plus requested effects without depending on concrete AppKit controllers or system adapters.
- [x] Automated tests exercise launch/readiness state and menu/Settings commands through the public engine seam.
- [x] The repository has a runnable test target and a documented local build/test command that passes from a clean checkout.
