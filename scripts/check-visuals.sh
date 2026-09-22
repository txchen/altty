#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:---check}"
[[ "$MODE" == --check || "$MODE" == --record ]] || { echo 'usage: check-visuals.sh [--check|--record]' >&2; exit 2; }
OUTPUT="$ROOT_DIR/.build/visual-qa/current"
BASELINE="$ROOT_DIR/Tests/Fixtures/VisualBaselines/macos-$(sw_vers -productVersion | cut -d. -f1)"
mkdir -p "$OUTPUT"
BUILD_OPTIONS=()
if [[ -n "${ALTTY_SWIFT_BUILD_SYSTEM:-}" ]]; then BUILD_OPTIONS+=(--build-system "$ALTTY_SWIFT_BUILD_SYSTEM"); fi
swift build ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"}
BUILD_DIR="$ROOT_DIR/.build/$(uname -m)-apple-macosx/debug"
xcrun swiftc -parse-as-library -enable-testing -I "$BUILD_DIR/Modules" -c Tests/Fixtures/VisualRegressionProbe.swift -o .build/visual-qa/probe.o
xcrun swiftc .build/visual-qa/probe.o "$BUILD_DIR"/Altty.build/*.swift.o -o .build/visual-qa/probe
# Clear generated images only; stale diff files must not masquerade as new scenarios.
find "$OUTPUT" -maxdepth 1 -type f -name '*.png' -delete
.build/visual-qa/probe "$OUTPUT"
if [[ "$MODE" == --record ]]; then
  mkdir -p "$BASELINE"
  cp "$OUTPUT"/*.png "$OUTPUT/environment.json" "$BASELINE/"
  echo "Recorded $BASELINE; inspect images before accepting this update."
else
  python3 scripts/compare-visuals.py "$BASELINE" "$OUTPUT"
fi
