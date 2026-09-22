#!/usr/bin/env bash
set -euo pipefail

die() { echo "release verification failed: $*" >&2; exit 1; }

ARTIFACT="${1:?usage: verify-release.sh <app-or-zip> <version> <build> [--distribution]}"
VERSION="${2:?missing version}"
BUILD_VERSION="${3:?missing build version}"
DISTRIBUTION="${4:-}"
EXPECTED_NAME="Altty-$VERSION-arm64.zip"
TEMP_DIR=""
trap '[[ -z "$TEMP_DIR" ]] || rm -rf "$TEMP_DIR"' EXIT

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be MAJOR.MINOR.PATCH"
[[ "$BUILD_VERSION" =~ ^[0-9]+$ ]] || die "build version must be an integer"

if [[ "$ARTIFACT" == *.zip ]]; then
  [[ "$(basename "$ARTIFACT")" == "$EXPECTED_NAME" ]] || die "artifact must be named $EXPECTED_NAME"
  TEMP_DIR="$(mktemp -d)"
  ditto -x -k "$ARTIFACT" "$TEMP_DIR"
  [[ "$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" == 1 ]] || die "ZIP must contain only Altty.app"
  APP="$TEMP_DIR/Altty.app"
else
  APP="$ARTIFACT"
fi

[[ -d "$APP" ]] || die "Altty.app is missing"
PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/Altty"
[[ -f "$PLIST" && -x "$BINARY" ]] || die "bundle contents are incomplete"
for notice in LICENSE NOTICE; do
  [[ -s "$APP/Contents/Resources/ThirdParty/ScrollReverser/$notice" ]] || die "Scroll Reverser $notice is missing"
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == "app.altty.macos" ]] || die "production bundle identifier mismatch"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "$VERSION" ]] || die "short version mismatch"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")" == "$BUILD_VERSION" ]] || die "build version mismatch"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" == "15.0" ]] || die "minimum system version mismatch"
[[ "$(lipo -archs "$BINARY")" == "arm64" ]] || die "binary is not arm64-only"
otool -l "$BINARY" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}' | grep -qx '15.0' || die "binary deployment target is not macOS 15.0"

codesign --verify --deep --strict "$APP"
SIGNATURE_DETAILS="$(codesign -dvv "$APP" 2>&1)"
grep -q 'flags=.*runtime' <<<"$SIGNATURE_DETAILS" || die "hardened runtime is not enabled"
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
for forbidden in com.apple.security.app-sandbox com.apple.security.get-task-allow com.apple.security.cs.disable-library-validation com.apple.security.cs.allow-jit com.apple.security.cs.allow-unsigned-executable-memory com.apple.security.cs.allow-dyld-environment-variables; do
  if grep -q "$forbidden" <<<"$ENTITLEMENTS"; then die "forbidden entitlement: $forbidden"; fi
done

if find "$APP" -type f \( -name '*.dSYM' -o -name '*.p12' -o -name '*.mobileprovision' -o -iname '*sparkle*' \) | grep -q .; then
  die "bundle contains debug, signing, or updater residue"
fi
while IFS= read -r bundled_file; do
  relative_path="${bundled_file#"$APP/"}"
  case "$relative_path" in
    Contents/Info.plist|Contents/MacOS/Altty|Contents/_CodeSignature/CodeResources|Contents/CodeResources) ;;
    Contents/Resources/ThirdParty/ScrollReverser/LICENSE|Contents/Resources/ThirdParty/ScrollReverser/NOTICE) ;;
    *) die "unexpected bundle content: $relative_path" ;;
  esac
done < <(find "$APP" -type f -print)
if [[ "$DISTRIBUTION" == "--distribution" ]]; then
  grep -q '^Authority=Developer ID Application:' <<<"$SIGNATURE_DETAILS" || die "Developer ID Application signature missing"
  grep -q '^Timestamp=' <<<"$SIGNATURE_DETAILS" || die "secure timestamp missing"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
fi

echo "Verified $ARTIFACT"
