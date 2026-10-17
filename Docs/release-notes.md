# Altty 0.2.0

Control the pointer from your keyboard with the new Mouse Mode, including places
where keyboard hints cannot reach.

## Mouse Mode

- Enter and exit with a shortcut you choose in Settings.
- Hold **WASD** to move. Hold **U** for precise movement or **I** to move faster.
- Press **J** for a left click or **K** for a right click. Stay in Mouse Mode
  after clicking, ready for the next action.
- Press **F**, then type a hint label to move directly to an element. This only
  moves the pointer; press **J** or **K** when you want to click.
- Press **Esc** to return from hints, then **Esc** again to exit. Your recorded
  Mouse Mode shortcut exits directly from either state.

Mouse Mode is off by default. Enable it in **Settings → General**, then record
**Toggle Mouse Mode** in **Settings → Shortcuts**. It needs Accessibility access.
Dragging and keyboard scrolling are not included in this release.

## A quieter menu bar indicator

Altty keeps its familiar stacked-card icon. The front card turns blue while Mouse
Mode is active and returns to monochrome when you exit. There is no floating
instruction panel; the controls are listed in Settings. The menu bar icon is
also better aligned and uses less horizontal space.

Standalone keyboard hints retain their existing select-then-Return-to-click
behavior. Window switching and mouse wheel reversal work as before.

## Install or update

Requires **Apple Silicon and macOS 15 or later**. Intel Macs are not supported.

After the Homebrew tap has updated, install with:

```sh
brew install --cask txchen/tap/altty
open /Applications/Altty.app
```

For an existing installation, quit Altty, then run:

```sh
brew update
brew upgrade --cask altty
open /Applications/Altty.app
```

You can also download `Altty-0.2.0-arm64.zip` from this release and move
**Altty.app** to **Applications**. Grant Accessibility access if macOS asks.
Mouse wheel reversal additionally needs Input Monitoring access.
