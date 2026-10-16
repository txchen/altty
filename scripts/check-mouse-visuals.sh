#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
OUTPUT="$ROOT_DIR/.build/mouse-visuals/current"
mkdir -p "$OUTPUT"
BUILD_OPTIONS=()
if [[ -n "${ALTTY_SWIFT_BUILD_SYSTEM:-}" ]]; then BUILD_OPTIONS+=(--build-system "$ALTTY_SWIFT_BUILD_SYSTEM"); fi
swift build ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"}
BUILD_DIR="$ROOT_DIR/.build/$(uname -m)-apple-macosx/debug"
xcrun swiftc -parse-as-library -enable-testing -I "$BUILD_DIR/Modules" -c Tests/Fixtures/VisualRegressionProbe.swift -o .build/mouse-visuals/probe.o
xcrun swiftc .build/mouse-visuals/probe.o "$BUILD_DIR"/Altty.build/*.swift.o -o .build/mouse-visuals/probe
ALTTY_MOUSE_VISUALS=1 .build/mouse-visuals/probe "$OUTPUT"
