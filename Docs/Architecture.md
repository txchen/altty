# Altty Architecture

Altty is intentionally small: it is a menu bar AppKit app with a title-list switcher. It uses Accessibility to inspect and focus windows, and does not use ScreenCaptureKit, Screen Recording permission, or SkyLight.

## Modules

- `Application`: app lifecycle, menu bar, command routing.
- `Input`: global `Option+Tab` hotkey and modifier-release detection.
- `Permissions`: Accessibility permission checks and System Settings entry points.
- `Windows`: Accessibility-based window collection, app activation ordering, and focusing.
- `UI`: settings window, switcher panel, and row views.

## Runtime Flow

1. `AppDelegate` starts the menu bar item and hotkey listener.
2. `HotKeyController` captures `Option+Tab`.
3. `WindowSwitcher` asks `AXWindowProvider` for open windows.
4. `SwitcherWindowController` renders a compact AppKit panel.
5. Releasing Option calls `WindowFocuser.focus(_:)` for the selected item.

## Current Constraints

- The default shortcut is fixed to `Option+Tab`.
- Window enumeration depends on what each app exposes through Accessibility.
- Windows on other Spaces may be incomplete without private APIs.
- No thumbnails are supported by design.
