#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
scripts/build-hostile-fixture.sh
BUILD_OPTIONS=()
if [[ -n "${ALTTY_SWIFT_BUILD_SYSTEM:-}" ]]; then BUILD_OPTIONS+=(--build-system "$ALTTY_SWIFT_BUILD_SYSTEM"); fi
swift build ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"}
BUILD_DIR="$ROOT_DIR/.build/$(uname -m)-apple-macosx/debug"
xcrun swiftc -target "$(uname -m)-apple-macosx15.0" -parse-as-library -enable-testing -I "$BUILD_DIR/Modules" -c Tests/Fixtures/AXFixtureProbe.swift -o .build/qa/ax-probe.o
xcrun swiftc .build/qa/ax-probe.o "$BUILD_DIR"/Altty.build/*.swift.o -o .build/qa/ax-probe
REPORT="$ROOT_DIR/.build/qa/hostile-report.json"
rm -f "$REPORT"
.build/qa/HostileWindowApp.app/Contents/MacOS/HostileWindowApp "$REPORT" 2 20 900 4 > .build/qa/hostile-events.jsonl &
FIXTURE_PID=$!
trap 'kill "$FIXTURE_PID" 2>/dev/null || true' EXIT
set +e
.build/qa/ax-probe "$REPORT"
AX_STATUS=$?
set -e
wait "$FIXTURE_PID"
trap - EXIT
python3 - "$REPORT" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
assert report['phase'] == 'finished', report
assert report['created'] == report['destroyed'] == 22, report
assert not report['windows'], report
print('LIFECYCLE_PASSED: 22 real AppKit windows created and closed; fixture exited')
PY
if [[ "$AX_STATUS" == 77 ]]; then
  echo 'AX integration remains unverified; lifecycle validation passed.'
  exit 77
fi
exit "$AX_STATUS"
