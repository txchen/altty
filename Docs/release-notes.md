# Altty 0.2.4

This release fixes switching back to a window with an open modal sheet.

## Fixes

- Altty now recognizes a focused sheet as part of its parent window. Apps such
  as Paseo no longer report a failed switch when the sheet has focus.

## Known limitation

On macOS 27, macOS withholds global shortcuts that use only Option or
Option-Shift while a password field has focus. This includes the default
⌥ Tab and ⌥ `, and Option shortcuts in other apps. Altty cannot receive them
until the field loses focus.

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

You can also download `Altty-0.2.4-arm64.zip` from this release and move
**Altty.app** to **Applications**. Grant Accessibility access if macOS asks.
Mouse wheel reversal additionally needs Input Monitoring access.
