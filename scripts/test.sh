#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/$(uname -m)-apple-macosx/debug"
RUNNER_OBJECT="$ROOT_DIR/.build/AlttyTestRunner.o"
RUNNER_BINARY="$ROOT_DIR/.build/altty-tests"
FOCUS_PROBE_OBJECT="$ROOT_DIR/.build/ImmediateFocusSmokeProbe.o"
FOCUS_PROBE_BINARY="$ROOT_DIR/.build/immediate-focus-smoke-probe"

if [[ -d /Applications/Xcode.app/Contents/Developer/Library/Developer/Frameworks/Testing.framework ]]; then
  DEVELOPER_FRAMEWORKS=/Applications/Xcode.app/Contents/Developer/Library/Developer/Frameworks
else
  DEVELOPER_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
fi

cd "$ROOT_DIR"

if [[ "${ALTTY_RUN_SHORTCUT_SMOKE:-0}" == "1" ]]; then
  PROBE_APP="$ROOT_DIR/.build/ShortcutPassThroughProbe.app"
  PROBE_CONTENTS="$PROBE_APP/Contents"
  mkdir -p "$PROBE_CONTENTS/MacOS"
  cp Tests/Fixtures/ShortcutPassThroughProbe-Info.plist "$PROBE_CONTENTS/Info.plist"
  xcrun swiftc \
    -parse-as-library \
    -framework AppKit \
    Tests/Fixtures/ShortcutPassThroughProbe.swift \
    -o "$PROBE_CONTENTS/MacOS/ShortcutPassThroughProbe"
  export ALTTY_SHORTCUT_PROBE_APP="$PROBE_APP"
fi

# Command Line Tools can compile Swift Testing targets but do not include the
# xctest host. Build through SwiftPM, then link the generated objects to the
# Swift Testing entry point so the same tests run with either CLT or Xcode.
ALTTY_RUN_FOCUS_SMOKE=0 \
ALTTY_RUN_CURRENT_APP_FOCUS_SMOKE=0 \
swift test --enable-swift-testing
if [[ "${ALTTY_RUN_FOCUS_SMOKE:-0}" == "1" \
    || "${ALTTY_RUN_CURRENT_APP_FOCUS_SMOKE:-0}" == "1" ]]; then
  xcrun swiftc \
    -parse-as-library \
    -enable-testing \
    -I "$BUILD_DIR/Modules" \
    -c Tests/Fixtures/ImmediateFocusSmokeProbe.swift \
    -o "$FOCUS_PROBE_OBJECT"
  xcrun swiftc \
    "$FOCUS_PROBE_OBJECT" \
    "$BUILD_DIR"/Altty.build/*.swift.o \
    -o "$FOCUS_PROBE_BINARY"
  export ALTTY_FOCUS_SMOKE_PROBE="$FOCUS_PROBE_BINARY"
fi
xcrun swiftc \
  -parse-as-library \
  -F "$DEVELOPER_FRAMEWORKS" \
  -c Tests/TestRunner/main.swift \
  -o "$RUNNER_OBJECT"
xcrun swiftc \
  "$RUNNER_OBJECT" \
  "$BUILD_DIR"/AlttyTests.build/*.swift.o \
  "$BUILD_DIR"/Altty.build/*.swift.o \
  -F "$DEVELOPER_FRAMEWORKS" \
  -framework Testing \
  -Xlinker -rpath \
  -Xlinker "$DEVELOPER_FRAMEWORKS" \
  -o "$RUNNER_BINARY"

exec "$RUNNER_BINARY" "$@"
