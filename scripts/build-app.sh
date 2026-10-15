#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${ALTTY_APP_DIR:-$ROOT_DIR/.build/Altty.app}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
VERSION="${ALTTY_VERSION:-0.0.0-dev}"
BUILD_VERSION="${ALTTY_BUILD_VERSION:-0}"
BUNDLE_IDENTIFIER="${ALTTY_BUNDLE_IDENTIFIER:-app.altty.macos.dev}"
SIGNING_IDENTITY="${ALTTY_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" && "$BUNDLE_IDENTIFIER" == "app.altty.macos.dev" && -f "$ROOT_DIR/.altty-signing-identity" ]]; then
  SIGNING_IDENTITY="$(cat "$ROOT_DIR/.altty-signing-identity")"
  [[ -n "$SIGNING_IDENTITY" ]] || { echo ".altty-signing-identity must not be empty" >&2; exit 1; }
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$VERSION" != "0.0.0-dev" ]]; then
  echo "Invalid ALTTY_VERSION: $VERSION" >&2
  exit 1
fi
if [[ ! "$BUILD_VERSION" =~ ^[0-9]+$ ]]; then
  echo "ALTTY_BUILD_VERSION must be a non-negative integer" >&2
  exit 1
fi

cd "$ROOT_DIR"
BUILD_OPTIONS=()
if [[ -n "${ALTTY_SWIFT_BUILD_SYSTEM:-}" ]]; then
  BUILD_OPTIONS+=(--build-system "$ALTTY_SWIFT_BUILD_SYSTEM")
fi
swift build -c release --arch arm64 ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"}

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp -R "$ROOT_DIR/Resources/ThirdParty" "$RESOURCES_DIR/ThirdParty"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT_DIR/.build/arm64-apple-macosx/release/Altty" "$MACOS_DIR/Altty"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"

sign_args=(--force --sign "$SIGNING_IDENTITY" --options runtime)
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  sign_args+=(--timestamp=none)
else
  sign_args+=(--timestamp)
fi
while IFS= read -r -d '' nested_code; do
  codesign "${sign_args[@]}" "$nested_code"
done < <(find "$CONTENTS_DIR" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.xpc' -o -name '*.appex' \) -print0)
codesign "${sign_args[@]}" --entitlements "$ROOT_DIR/Resources/Release.entitlements" "$APP_DIR"

echo "$APP_DIR"
