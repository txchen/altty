#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
BUILD_OPTIONS=()
if [[ -n "${ALTTY_SWIFT_BUILD_SYSTEM:-}" ]]; then BUILD_OPTIONS+=(--build-system "$ALTTY_SWIFT_BUILD_SYSTEM"); fi
swift build ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"}
BUILD_DIR="$ROOT_DIR/.build/$(uname -m)-apple-macosx/debug"
OUTPUT="$ROOT_DIR/.build/self-window-regression"
mkdir -p "$OUTPUT"
xcrun swiftc -parse-as-library -enable-testing -I "$BUILD_DIR/Modules" -c Tests/Fixtures/SelfWindowFocusProbe.swift -o "$OUTPUT/probe.o"
xcrun swiftc "$OUTPUT/probe.o" "$BUILD_DIR"/Altty.build/*.swift.o -o "$OUTPUT/probe"
exec "$OUTPUT/probe"
