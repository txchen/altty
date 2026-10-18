# Altty 0.2.1

This release fixes two window-switching bugs.

## Fixes

- **No more duplicate browser windows.** With the find bar open in Brave,
  Chrome or another Chromium browser, the switcher listed the browser twice.
  Choosing the extra entry showed "Unable to switch to that window". Child
  windows such as the find bar no longer appear in the list.
- **A quick Option-Tab switches reliably.** Sometimes the switcher started on
  the window you were already in, so a quick press did nothing and the list
  opened with the current app selected. This happened when focus had moved to
  a browser find bar, or to the overlay of a menu bar utility such as
  MonitorControl. Altty now always starts from the frontmost app's window and
  selects the next one.

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

You can also download `Altty-0.2.1-arm64.zip` from this release and move
**Altty.app** to **Applications**. Grant Accessibility access if macOS asks.
Mouse wheel reversal additionally needs Input Monitoring access.
