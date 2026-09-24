#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
scripts/build-hostile-fixture.sh
BUILD_OPTIONS=()
if [[ -n "${ALTTY_SWIFT_BUILD_SYSTEM:-}" ]]; then BUILD_OPTIONS+=(--build-system "$ALTTY_SWIFT_BUILD_SYSTEM"); fi
swift build ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"}
BUILD_DIR="$ROOT_DIR/.build/$(uname -m)-apple-macosx/debug"
OUTPUT="$ROOT_DIR/.build/focus-regression"
mkdir -p "$OUTPUT"
xcrun swiftc -parse-as-library -enable-testing -I "$BUILD_DIR/Modules" -c Tests/Fixtures/WindowFocusRegressionProbe.swift -o "$OUTPUT/probe.o"
xcrun swiftc "$OUTPUT/probe.o" "$BUILD_DIR"/Altty.build/*.swift.o -o "$OUTPUT/probe"
rm -f "$OUTPUT/one.json" "$OUTPUT/two.json"
.build/qa/HostileWindowApp.app/Contents/MacOS/HostileWindowApp "$OUTPUT/one.json" 3 0 0 60 > "$OUTPUT/one.log" 2>&1 &
FIRST_PID=$!
.build/qa/HostileWindowApp.app/Contents/MacOS/HostileWindowApp "$OUTPUT/two.json" 3 0 0 60 > "$OUTPUT/two.log" 2>&1 &
SECOND_PID=$!
trap 'kill "$FIRST_PID" "$SECOND_PID" 2>/dev/null || true' EXIT
for _ in {1..50}; do
  [[ -f "$OUTPUT/one.json" && -f "$OUTPUT/two.json" ]] && break
  sleep 0.1
done
"$OUTPUT/probe" "$OUTPUT/one.json" "$OUTPUT/two.json"
