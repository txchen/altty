#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT_DIR/.build/qa/HostileWindowApp.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -target "$(uname -m)-apple-macosx15.0" -parse-as-library -framework AppKit "$ROOT_DIR/Tests/Fixtures/HostileWindowApp.swift" -o "$APP/Contents/MacOS/HostileWindowApp"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.altty.qa.hostile-window</string>
<key>CFBundleName</key><string>Altty QA Fixture</string>
<key>CFBundleExecutable</key><string>HostileWindowApp</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none "$APP"
echo "$APP"
