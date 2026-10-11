Status: ready-for-agent

## Problem Statement

Clicking UI elements requires leaving the keyboard. Shortcat solves this with a
search palette and Neru with Vimium-style hints, but neither belongs to Altty,
and Altty only cares about macOS. Altty needs a native, pure-Swift hint mode:
press a user-recorded shortcut, see short labels on the clickable elements of
the frontmost window, type a label to select an element, then press Enter
(optionally with modifiers) to perform a mouse action on it.

## Interaction

1. The user presses the Hint Shortcut (unbound by default; recorded in
   Settings → Shortcuts, Shift allowed, e.g. ⌃⌥⇧⌘F).
2. Altty scans the Hint Scope and shows a Hint Label on every Hint Target.
3. Typing letters filters labels by prefix. A complete label selects its
   target, which is highlighted. Typing another complete label moves the
   selection. A letter that matches no label is ignored. Backspace removes one
   typed letter; with no typed letters it clears the selection.
4. With a selection:

   | Input | Effect |
   |---|---|
   | Enter | Default Action |
   | Enter twice within `NSEvent.doubleClickInterval` | double click at the target's midpoint |
   | ⌃ + Enter | right click at the midpoint |
   | ⌘ / ⇧ / ⌥ (any combination) + Enter | click at the midpoint with those modifiers |
   | tap ⌃ alone | move the cursor to the midpoint (hover) |

   Enter with no selection does nothing.
5. Escape, the Hint Shortcut, a ⌘-chord other than ⌘+Enter, a frontmost-app
   change or a click anywhere ends the Hint Session without acting. Every action
   ends the session; the cursor is not restored afterwards.

Default Action (Shortcat's rule): AXPress for buttons, AXPress for menu items,
AXRaise for windows, otherwise a synthesized left click at the midpoint.
Modifier, right and double clicks are always synthesized CGEvents. A double
click is only possible on synthesized-click targets: the first Enter clicks
immediately and Altty keeps capturing Enter for one double-click interval;
any other key ends that interval and passes through.

## Hint Scope

- The frontmost application's focused window, its sheets and popovers, and a
  currently open menu.
- The top-level items of the frontmost application's menu bar. Their children
  are never read, because reading them opens the menu; pressing the Hint
  Shortcut while a menu is open hints that menu's items instead.
- Only elements visible on screen: clipped to the window and to every
  enclosing scroll area. Labels appear on whatever display the element is on.

## Labels and appearance

- Home-row alphabet `asdfghjkl`, prefix-free mixed-length labels assigned in
  top-to-bottom, left-to-right order (Neru's "normal" generator).
- Fixed black-on-yellow badges with a grey border; the selected target uses a
  distinct highlight. No style settings.

## Electron and Chromium

On a Hint Session against an Electron app (bundle contains
`Electron Framework.framework`), set `AXManualAccessibility = true` on the
application element. Against a Chromium browser, set
`AXEnhancedUserInterface = true` for the scan and restore the previous value
afterwards. Only applications the user actually hints are touched.

## Integration

- Hint Mode is optional. It is off by default and enabled with a checkbox in
  Settings → General. The Hint Shortcut is unbound by default and recorded by
  the user in Settings → Shortcuts. Nothing is registered unless the mode is
  enabled and a shortcut is recorded.
- Settings live in `GeneralSettings.hintMode: HintModeSettings` and decode with
  `decodeIfPresent` (the v5 precedent), so no schema bump.
- Readiness depends on Accessibility only, independent of SkyLight, like Mouse
  Wheel Reversal.
- Exception Rule Ignore behavior also disables the Hint Shortcut.
- The Hint Shortcut is persisted next to the switcher pair (settings schema
  bump) and validated against both switcher chords and their Shift-reverse
  variants.

## To settle by prototype before building

- Keyboard capture: active CGEventTap versus a key non-activating panel. The
  target window must keep its key appearance.
- Scan latency on real apps (Finder, Safari, Brave, VS Code, Obsidian, System
  Settings) and the timeout budget per AX call.
- Electron/Chromium: element counts on freshly launched processes before and
  after setting the attribute, and how long the tree takes to appear. Shortcat
  being installed can leave the attribute set on long-running processes.
- Whether the Hint Shortcut fires during menu tracking.
- A probe run from the pi/Ghostty context on macOS 27.0.1 saw `AXFocusedWindow`
  return the application element itself; recheck from the Altty bundle.
- Secure input (focused password field) behavior.

## Out of scope

Text search, Continuous Mode, scrolling and arrow-key chords, Dock, Notification
Center, Mission Control, window-list hints, emoji, style settings, cursor
restore, a default shortcut.

## Glossary candidates

Hint Shortcut, Hint Session, Hint Scope, Hint Target, Hint Label, Default
Action. Add to `CONTEXT.md` when implementation starts.
