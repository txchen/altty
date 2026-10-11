#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

swiftc -O "$ROOT_DIR/scripts/render-app-icon.swift" -o "$WORK_DIR/render-app-icon"
"$WORK_DIR/render-app-icon" "$WORK_DIR/AppIcon.iconset"
iconutil -c icns "$WORK_DIR/AppIcon.iconset" -o "$ROOT_DIR/Resources/AppIcon.icns"
echo "$ROOT_DIR/Resources/AppIcon.icns"
