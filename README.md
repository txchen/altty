# Altty

Altty is a small macOS window switcher focused on title-list switching. It uses Accessibility for window discovery and focusing, and deliberately avoids screen-recording permissions.

## Build

```sh
scripts/build-app.sh
```

The app bundle is created at:

```text
.build/Altty.app
```

## Current Scope

- Menu bar app
- Settings window
- Accessibility permission prompt
- `Option+Tab` global shortcut
- Title-list window switcher
- No thumbnails and no Screen Recording permission
