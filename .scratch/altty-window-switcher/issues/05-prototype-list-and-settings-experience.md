Status: resolved
Type: prototype
Parent: ../map.md
Blocked by: 03, 04

## Question

What concrete list panel, row content, state indicators, selection treatment, sizing, overflow behavior, multi-display placement, menu-bar menu, and Settings layout make the agreed behavior understandable and fast without thumbnails, while remaining visually independent from AltTab?

## Answer

Selected **A — Compact Palette** from the three-way throwaway UI prototype captured on branch `codex/altty-ui-prototype` at commit `58e0a0e`.

### Switcher panel

- Use a compact, centered vertical list styled as a native translucent macOS panel, visually independent from AltTab's thumbnail grid.
- Header shows the active mode on the left and its configured shortcut on the right.
- Each row shows the application icon, window title as primary text, application name as secondary text, and compact trailing state badges for Space, minimized, hidden and fullscreen state.
- Selection uses a full-row macOS accent-color highlight; selected secondary text and badges remain legible without adding a separate focus border.
- Truncate long title and application text to one line. Keep icons and badges fixed while the title column absorbs available width.
- Size width to a readable compact range rather than content width. Show roughly 6–8 rows before vertical overflow; scroll without changing row density and keep the selected row visible.
- Center on the screen containing the pointer when invoked, falling back to the screen containing the invoking window, then the primary screen. Do not span displays.
- The panel contains no search field, thumbnails, previews, window controls or live-focus surface.

### Settings

- Use a conventional macOS Settings window with a left sidebar: General, Shortcuts, Exceptions and About.
- General contains Accessibility state/action, start at login, and list-display basics. Shortcuts contains the two recorder controls and inline conflict errors.
- Reuse the management-first Exceptions content demonstrated by Variant B inside A's sidebar shell: searchable list is unnecessary, but rows show icon/name, bundle ID, exact/prefix identity, and concise Hide/Ignore summary, with Add/Edit/Delete actions.
- About contains version, project/support links and Check for Updates, which opens the release page in the first release.
- Permission warnings and malformed-setting warnings are inline in the relevant pane rather than modal at launch.

### Menu-bar menu

- Show a compact readiness/permission status, Settings, Accessibility status/action, Check for Updates and Quit.
- Do not duplicate switcher candidates or Exception editing in the menu.

### Prototype disposition

- Variant A won for scanning density, familiar macOS structure and suitability for long lists and titles.
- Variant B contributed its Exceptions information hierarchy; its wide inspector switcher was rejected as too visually heavy.
- Variant C was rejected because a horizontal HUD hides too many windows and state details as candidate count grows.
- The prototype is decision evidence only. Production AppKit views must be implemented afresh from this contract.
