#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:?usage: finalize-release.sh APP_DIR VERSION BUILD_VERSION OUTPUT_DIR [--replace] [--distribution]}"
VERSION="${2:?missing version}"
BUILD_VERSION="${3:?missing build version}"
OUTPUT_DIR="${4:?missing output directory}"
shift 4
REPLACE=0
VERIFY_MODE=""
for option in "$@"; do
  case "$option" in
    --replace) REPLACE=1 ;;
    --distribution) VERIFY_MODE="--distribution" ;;
    *) echo "unknown option: $option" >&2; exit 1 ;;
  esac
done

ARTIFACT="Altty-$VERSION-arm64.zip"
mkdir -p "$OUTPUT_DIR"
if [[ -e "$OUTPUT_DIR/$ARTIFACT" && "$REPLACE" != 1 ]]; then
  echo "refusing to overwrite $OUTPUT_DIR/$ARTIFACT" >&2
  exit 1
fi

"$ROOT_DIR/scripts/verify-release.sh" "$APP_DIR" "$VERSION" "$BUILD_VERSION" $VERIFY_MODE
rm -f "$OUTPUT_DIR/$ARTIFACT"
ditto -c -k --keepParent "$APP_DIR" "$OUTPUT_DIR/$ARTIFACT"
"$ROOT_DIR/scripts/verify-release.sh" "$OUTPUT_DIR/$ARTIFACT" "$VERSION" "$BUILD_VERSION" $VERIFY_MODE
SHA256="$(shasum -a 256 "$OUTPUT_DIR/$ARTIFACT" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$ARTIFACT" > "$OUTPUT_DIR/checksums.txt"
(cd "$OUTPUT_DIR" && shasum -a 256 -c checksums.txt)
printf '{"version":"%s","build_version":"%s","artifact":"%s","sha256":"%s","git_sha":"%s"}\n' \
  "$VERSION" "$BUILD_VERSION" "$ARTIFACT" "$SHA256" "${GITHUB_SHA:-$(git -C "$ROOT_DIR" rev-parse HEAD)}" \
  > "$OUTPUT_DIR/release-metadata.json"
echo "$OUTPUT_DIR/$ARTIFACT"
