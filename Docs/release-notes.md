# Altty 0.2.3

This release keeps Altty's shortcuts working while another app uses Secure
Input.

## Fixes

- **Shortcuts work while Secure Input is on.** Password fields, password
  managers and some terminals turn on macOS Secure Input. While it was on,
  Altty ignored even the shortcuts that macOS still delivered, such as ones
  that use Control or Command. Altty now handles them, and releasing the held
  modifiers still chooses the selected window.

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

You can also download `Altty-0.2.3-arm64.zip` from this release and move
**Altty.app** to **Applications**. Grant Accessibility access if macOS asks.
Mouse wheel reversal additionally needs Input Monitoring access.
