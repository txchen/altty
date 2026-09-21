#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?usage: render-cask.sh VERSION SHA256 [REPOSITORY] [URL]}"
SHA256="${2:?missing SHA-256}"
REPOSITORY="${3:-altty/altty}"
URL="${4:-https://github.com/$REPOSITORY/releases/download/$VERSION/Altty-$VERSION-arm64.zip}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || exit 1
cat <<EOF
cask "altty" do
  version "$VERSION"
  sha256 "$SHA256"

  url "$URL"
  name "Altty"
  desc "Native Apple-silicon menu-bar window switcher"
  homepage "https://github.com/$REPOSITORY"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "Altty.app"

  zap trash: [
    "~/Library/Application Support/app.altty.macos",
    "~/Library/Caches/app.altty.macos",
    "~/Library/Logs/app.altty.macos",
    "~/Library/Preferences/app.altty.macos.plist",
  ]
end
EOF
