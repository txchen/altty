# Use Altty

## Mouse wheel direction

In Settings → General, enable **Reverse mouse wheel direction** to reverse mouse
scrolling on both axes, independently of the window switcher. The single toggle
is off by default and persists across restarts. Set your preferred trackpad
direction in macOS System Settings; Altty does not change that preference.

This feature requires Accessibility and Input Monitoring. If General shows a
permission warning, use the permission button, enable Altty in System Settings,
then choose Check Readiness (or restart Altty if macOS requests it).

Quit Scroll Reverser or disable other mouse-direction tools before testing to
avoid double reversal. Check a long page in Safari and a Finder window: the
mouse should reverse, while two-finger trackpad scrolling and its momentum
should remain unchanged. Also check horizontal scrolling, turning the toggle
off, and restarting Altty with it on.

Mouse/trackpad identification and the HID compatibility path are adapted from
[Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser/tree/187bf3945b6107cd8486327c6165f32e523535a4),
under Apache-2.0. This uses upstream touch-timing heuristics, not guaranteed
per-device identification; third-party drivers and unusual gesture settings
still need hardware validation. License and attribution ship in the app's
`Contents/Resources/ThirdParty/ScrollReverser` directory.

## Keyboard hints

Hint Mode labels clickable elements so they can be clicked from the keyboard.
It is off by default. Turn on **Enable keyboard hints** in Settings → General,
then record a shortcut for **Show hints** in Settings → Shortcuts. No shortcut
is registered until both are set. Hint Mode needs only Accessibility.

Press the shortcut to label the frontmost window, its sheets and popovers and
its menu bar items. With a menu open, only that menu is labelled. Type a label
to select an element, then:

| Key | Action |
|---|---|
| Return | Default action (press buttons and menu items, otherwise click) |
| Return twice | Double click |
| ⌃ Return | Right click |
| ⌘ / ⇧ / ⌥ Return | Click with those modifiers |
| Tap ⌃ | Move the pointer onto the element |
| Escape, the shortcut again | Cancel |

Typing another label moves the selection; Delete removes a typed letter, then
the selection. The pointer is not moved back after a click.

Electron apps get `AXManualAccessibility` and Chromium browsers get a temporary
`AXEnhancedUserInterface` the first time they are hinted, because both build
their web-content tree only for assistive tools. Test those apps with a freshly
launched process: tools such as Shortcat leave the attribute set.

Scan a running app with the production scanner without showing any UI:

```sh
ALTTY_RUN_HINT_SCAN_SMOKE=1 ALTTY_HINT_SCAN_PID=<pid> \
scripts/test.sh --filter HintScanSmoke
```

## Default exceptions

Fresh settings include fullscreen shortcut pass-through for Screen Sharing,
Microsoft Remote Desktop / Windows App, TeamViewer, VirtualBox, Parallels,
Citrix Viewer (both bundle IDs), Amazon DCV, VMware Fusion and UTM. These apps'
windows remain visible in Altty; only their foreground fullscreen sessions receive
shortcuts directly. Parallels uses the `com.parallels.` prefix; other entries use
exact bundle identifiers. McAfee's Safari helper windows are hidden.

The recommendations follow [AltTab v11.7.1's default exceptions](https://github.com/lwouis/alt-tab-macos/blob/v11.7.1/src/preferences/Preferences.swift).
Altty does not need AltTab's windowless-Finder rule because it only lists real windows.
All entries can be edited or deleted in Settings → Exceptions. Saved lists, including
an intentionally empty list and lists migrated from older versions, are preserved.
These defaults are also used by the existing safe-defaults recovery path when a
settings file cannot be loaded; the original invalid file is preserved for diagnosis.

## Move the pointer with the keyboard

Turn on **Enable Mouse Mode** in Settings → General. In Settings → Shortcuts,
record **Toggle Mouse Mode**. Mouse Mode needs Accessibility permission.

Press your recorded shortcut, then use these keys. The Altty icon in the menu bar turns blue while Mouse Mode is active, including inside hints. Press the shortcut again to exit.

| Key | Action |
|---|---|
| Hold W, A, S, or D | Move up, left, down, or right |
| Hold U | Move slowly |
| Hold I | Move quickly |
| J | Left click once |
| K | Right click once |
| F | Show hints for pointer placement |
| Escape in hints | Return to Mouse Mode |
| Escape in Mouse Mode | Exit |
| Recorded Mouse shortcut | Exit from either phase |

Release a movement key to stop that direction. Diagonal movement has the same
speed as movement along one axis. U takes priority when U and I are both held.
J and K do not repeat when held. Mouse Mode remains active after clicks and
when you change applications.

After F, type a complete label to move the pointer onto that element. This
does not click or activate the element. Mouse Mode resumes with movement
stopped. Release any held movement keys, then press them again to move.
Standalone keyboard hints keep their separate Return-to-click behavior.

A Command, Control, or Option chord that is not the Mouse shortcut exits Mouse
Mode and passes through to the application. Opening Altty's window switcher
also exits Mouse Mode. An Exception Rule with Ignore, permission loss, secure
input, sleep, or screen lock ends the session. Start a new session after the
condition clears. Mouse Mode does not drag, scroll, or use image recognition.
