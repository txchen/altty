#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: prepare-tap-update.sh VERSION SHA256 REPOSITORY TAP_DIRECTORY}"
SHA256="${2:?missing SHA-256}"
REPOSITORY="${3:?missing repository}"
TAP_DIR="${4:?missing tap directory}"
cd "$TAP_DIR"
# Preflight only a clean checkout; never accidentally stage unrelated changes.
test -z "$(git status --porcelain)"
EXISTING=false
if git ls-files --error-unmatch Casks/altty.rb >/dev/null 2>&1; then
  EXISTING=true
fi
mkdir -p Casks
"$ROOT_DIR/scripts/render-cask.sh" "$VERSION" "$SHA256" "$REPOSITORY" > Casks/altty.rb
# Include first publication in the same diff validation as upgrades.
git add --intent-to-add -- Casks/altty.rb
test "$(git diff --name-only)" = "Casks/altty.rb"
if [[ "$EXISTING" == true ]]; then
  if git diff --unified=0 -- Casks/altty.rb \
    | grep -E '^[+-][^+-]' \
    | grep -Ev '^[+-]  (version|sha256|url) '; then
    echo "Cask update changes more than release metadata" >&2
    exit 1
  fi
fi
git diff --check
git add -- Casks/altty.rb
