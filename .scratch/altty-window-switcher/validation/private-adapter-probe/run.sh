#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build="$root/.build"
architecture=${ARCHITECTURE:-$(uname -m)}
binary="$build/altty-private-adapter-probe-$architecture"

mkdir -p "$build"
xcrun swiftc \
  -O \
  -target "$architecture-apple-macos15.0" \
  -framework ApplicationServices \
  -framework CoreGraphics \
  "$root/Probe.swift" \
  -o "$binary"
codesign --force --sign - --options runtime --timestamp=none "$binary"
codesign --verify --strict --verbose=2 "$binary"
codesign -d --entitlements :- "$binary"
file "$binary"
"$binary"
