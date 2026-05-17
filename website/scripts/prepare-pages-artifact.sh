#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WEBSITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ROOT_DIR="$(cd "$WEBSITE_DIR/.." && pwd -P)"

OUT_DIR="$WEBSITE_DIR/out"
APPCAST_SOURCE="$ROOT_DIR/release/appcast.xml"
RELEASE_NOTES_SOURCE_DIR="$ROOT_DIR/release/release-notes"
CNAME_SOURCE="$WEBSITE_DIR/CNAME"

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "[prepare-pages] $*"
}

[[ -d "$OUT_DIR" ]] || die "Missing Next export output directory: $OUT_DIR (did next build produce it?)"
[[ -f "$APPCAST_SOURCE" ]] || die "Missing Sparkle appcast source: $APPCAST_SOURCE"
[[ -d "$RELEASE_NOTES_SOURCE_DIR" ]] || die "Missing release notes source directory: $RELEASE_NOTES_SOURCE_DIR"

if [[ -f "$CNAME_SOURCE" ]]; then
  cp "$CNAME_SOURCE" "$OUT_DIR/CNAME"
  info "Copied CNAME"
fi

touch "$OUT_DIR/.nojekyll"

cp "$APPCAST_SOURCE" "$OUT_DIR/appcast.xml"
info "Copied appcast.xml"

rm -rf "$OUT_DIR/release-notes"
mkdir -p "$OUT_DIR/release-notes"
cp -R "$RELEASE_NOTES_SOURCE_DIR/." "$OUT_DIR/release-notes/"
info "Copied release notes"

info "Done"
