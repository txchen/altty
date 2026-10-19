# Altty 0.2.2

This release fixes windows that went missing from the switcher after waking
your Mac.

## Fixes

- **All windows return after sleep.** After opening the lid or waking the Mac,
  the switcher could list only one or two windows. The others came back only
  after you clicked them. macOS hides window details from apps while the screen
  is locked, and Altty did not read them again after you unlocked. It now does
  this on unlock and on display wake.
- **Busy apps recover by themselves.** If an app is too slow to respond when
  Altty first reads its windows, Altty reads them again the next time you
  switch to that app.

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

You can also download `Altty-0.2.2-arm64.zip` from this release and move
**Altty.app** to **Applications**. Grant Accessibility access if macOS asks.
Mouse wheel reversal additionally needs Input Monitoring access.
