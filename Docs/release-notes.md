Altty is a lightweight menu-bar window switcher for Apple-silicon Macs running macOS 15 or later.

- Switch between windows with Option-Tab and between windows of the current app with Option-Grave.
- Configure shortcuts, application exceptions, adaptive window lists, keyboard hints, and mouse-only scroll reversal.
- Signed by Double Jump Academy and notarized by Apple.

Install after the Homebrew tap update completes:

```sh
brew install --cask txchen/tap/altty
open /Applications/Altty.app
```

On first launch, grant Altty Accessibility access in System Settings. Mouse scroll reversal also needs Input Monitoring. These permissions must be granted by the user.

Update with `brew update` followed by `brew upgrade --cask altty`. Quit Altty before upgrading, then reopen it.

Intel Macs are not supported by this release.
