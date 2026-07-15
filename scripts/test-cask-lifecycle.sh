#!/usr/bin/env bash
set -euo pipefail

CURRENT_CASK="${1:?usage: test-cask-lifecycle.sh CURRENT_CASK [PREVIOUS_CASK]}"
PREVIOUS_CASK="${2:-}"
SUPPORT_DIR="$HOME/Library/Application Support/app.altty.macos"
CACHE_DIR="$HOME/Library/Caches/app.altty.macos"
LOG_DIR="$HOME/Library/Logs/app.altty.macos"

brew install --cask "$CURRENT_CASK"
test -d /Applications/Altty.app
mkdir -p "$SUPPORT_DIR" "$CACHE_DIR" "$LOG_DIR"
touch "$SUPPORT_DIR/settings.json"
brew uninstall --cask altty
test -e "$SUPPORT_DIR/settings.json"

if [[ -n "$PREVIOUS_CASK" ]]; then
  brew install --cask "$PREVIOUS_CASK"
  brew upgrade --cask "$CURRENT_CASK"
else
  brew install --cask "$CURRENT_CASK"
fi

brew uninstall --zap --cask altty
test ! -e "$SUPPORT_DIR"
test ! -e "$CACHE_DIR"
test ! -e "$LOG_DIR"
! grep -q 'TCC' "$CURRENT_CASK"
