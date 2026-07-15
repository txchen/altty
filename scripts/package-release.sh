#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: package-release.sh VERSION BUILD_VERSION [OUTPUT_DIR]}"
BUILD_VERSION="${2:?missing build version}"
OUTPUT_DIR="${3:-$ROOT_DIR/.build/artifacts}"
ARTIFACT="Altty-$VERSION-arm64.zip"
APP_DIR="$ROOT_DIR/.build/release-work/Altty.app"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must be MAJOR.MINOR.PATCH" >&2; exit 1; }
[[ "$BUILD_VERSION" =~ ^[0-9]+$ ]] || { echo "build version must be an integer" >&2; exit 1; }
[[ ! -e "$OUTPUT_DIR/$ARTIFACT" ]] || { echo "refusing to overwrite $OUTPUT_DIR/$ARTIFACT" >&2; exit 1; }
mkdir -p "$(dirname "$APP_DIR")"

ALTTY_APP_DIR="$APP_DIR" \
ALTTY_VERSION="$VERSION" \
ALTTY_BUILD_VERSION="$BUILD_VERSION" \
ALTTY_BUNDLE_IDENTIFIER="app.altty.macos" \
"$ROOT_DIR/scripts/build-app.sh"
"$ROOT_DIR/scripts/finalize-release.sh" "$APP_DIR" "$VERSION" "$BUILD_VERSION" "$OUTPUT_DIR"
