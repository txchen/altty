#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/$(uname -m)-apple-macosx/debug"
RUNNER_OBJECT="$ROOT_DIR/.build/AlttyTestRunner.o"
RUNNER_BINARY="$ROOT_DIR/.build/altty-tests"

if [[ -d /Applications/Xcode.app/Contents/Developer/Library/Developer/Frameworks/Testing.framework ]]; then
  DEVELOPER_FRAMEWORKS=/Applications/Xcode.app/Contents/Developer/Library/Developer/Frameworks
else
  DEVELOPER_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
fi

cd "$ROOT_DIR"

# Command Line Tools can compile Swift Testing targets but do not include the
# xctest host. Build through SwiftPM, then link the generated objects to the
# Swift Testing entry point so the same tests run with either CLT or Xcode.
swift test --enable-swift-testing
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
