#!/usr/bin/env bash
set -euo pipefail

[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo "Run lifecycle tests only on disposable GitHub runners" >&2; exit 1; }
CURRENT_CASK="${1:?usage: test-cask-lifecycle.sh CURRENT_CASK [PREVIOUS_CASK]}"
PREVIOUS_CASK="${2:-}"
SUPPORT_DIR="$HOME/Library/Application Support/app.altty.macos"
CACHE_DIR="$HOME/Library/Caches/app.altty.macos"
LOG_DIR="$HOME/Library/Logs/app.altty.macos"
[[ ! -e /Applications/Altty.app && ! -e "$SUPPORT_DIR" ]] || { echo "Refusing to touch an existing installation" >&2; exit 1; }
export HOMEBREW_NO_AUTO_UPDATE=1
TAP="altty/ci"
TAP_SOURCE="$(mktemp -d "$RUNNER_TEMP/altty-tap.XXXXXX")"
mkdir -p "$TAP_SOURCE/Casks"
git -C "$TAP_SOURCE" init -q
git -C "$TAP_SOURCE" config user.name 'Altty CI'
git -C "$TAP_SOURCE" config user.email 'ci@example.invalid'
cp "$CURRENT_CASK" "$TAP_SOURCE/Casks/altty.rb"
git -C "$TAP_SOURCE" add Casks/altty.rb
git -C "$TAP_SOURCE" commit -qm 'Current cask'
brew tap "$TAP" "$TAP_SOURCE"
trap 'brew untap "$TAP" || true' EXIT
brew install --cask "$TAP/altty"
test -d /Applications/Altty.app
codesign --verify --deep --strict /Applications/Altty.app
xcrun stapler validate /Applications/Altty.app
spctl --assess --type execute --verbose=2 /Applications/Altty.app
mkdir -p "$SUPPORT_DIR" "$CACHE_DIR" "$LOG_DIR"
printf 'preserve-me\n' > "$SUPPORT_DIR/lifecycle-sentinel"
brew uninstall --cask "$TAP/altty"
grep -qx preserve-me "$SUPPORT_DIR/lifecycle-sentinel"

if [[ -n "$PREVIOUS_CASK" ]]; then
  cp "$PREVIOUS_CASK" "$TAP_SOURCE/Casks/altty.rb"
  git -C "$TAP_SOURCE" commit -qam 'Previous cask'
  git -C "$(brew --repository "$TAP")" pull --ff-only
  brew install --cask "$TAP/altty"
  cp "$CURRENT_CASK" "$TAP_SOURCE/Casks/altty.rb"
  git -C "$TAP_SOURCE" commit -qam 'Upgrade cask'
  git -C "$(brew --repository "$TAP")" pull --ff-only
  brew upgrade --cask "$TAP/altty"
else
  brew install --cask "$TAP/altty"
fi
grep -qx preserve-me "$SUPPORT_DIR/lifecycle-sentinel"
EXPECTED_VERSION="$(ruby -ne 'puts $1 if /^  version "([^"]+)"/' "$CURRENT_CASK")"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Altty.app/Contents/Info.plist)" = "$EXPECTED_VERSION"
brew uninstall --zap --cask "$TAP/altty"
test ! -e "$SUPPORT_DIR"
test ! -e "$CACHE_DIR"
test ! -e "$LOG_DIR"
! grep -q 'TCC' "$CURRENT_CASK"
