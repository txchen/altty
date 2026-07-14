# Altty

Altty is a native Apple-silicon menu-bar window switcher for macOS 15 and later.

## Build

```sh
scripts/build-app.sh
swift test
```

The app bundle is created at:

```text
.build/Altty.app
```

The build script produces an arm64 application at `.build/Altty.app`. `swift test`
runs the public `SwitcherEngine` tests.

## Current foundation

- Menu bar app
- Settings window
- Readiness status for Accessibility and WindowServer capability
- General, Shortcuts, Exceptions and About settings destinations
- Replaceable system-adapter boundaries assembled around `SwitcherEngine`
- No thumbnails and no Screen Recording permission
