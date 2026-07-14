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
4. AppKit Presentation renders immutable engine state in the menu and Settings shell.
5. Later implementation tickets fill the adapter protocols without moving system types into core state.

## Current Constraints

- The production shell reports WindowServer unavailable until the isolated SkyLight adapter is implemented.
- Shortcuts and switching sessions arrive in later implementation tickets.
- No thumbnails are supported by design.
