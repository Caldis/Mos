#!/usr/bin/env bash
# create_gh_draft.sh - Create a GitHub release draft
# Usage: create_gh_draft.sh <tag> <zip_path> <release_notes_md_file> [--prerelease]
set -euo pipefail

GITHUB_REPO="Caldis/Mos"

die() { echo "Error: $*" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || die "gh CLI not found"

TAG="${1:-}"
ZIP_PATH="${2:-}"
NOTES_FILE="${3:-}"
PRERELEASE=()

shift 3 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prerelease) PRERELEASE=(--prerelease); shift ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -n "$TAG" ]] || die "Usage: create_gh_draft.sh <tag> <zip_path> <notes_md_file> [--prerelease]"
[[ -f "$ZIP_PATH" ]] || die "Zip not found: $ZIP_PATH"
[[ -f "$NOTES_FILE" ]] || die "Notes file not found: $NOTES_FILE"

# Check if release already exists
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Updating..."
  gh release edit "$TAG" \
    --repo "$GITHUB_REPO" \
    --draft \
    --title "$TAG" \
    --notes-file "$NOTES_FILE" \
    ${PRERELEASE[@]+"${PRERELEASE[@]}"}
  # Upload/replace asset
  gh release upload "$TAG" "$ZIP_PATH" --repo "$GITHUB_REPO" --clobber
else
  gh release create "$TAG" "$ZIP_PATH" \
    --repo "$GITHUB_REPO" \
    --draft \
    --notes-file "$NOTES_FILE" \
    --title "$TAG" \
    ${PRERELEASE[@]+"${PRERELEASE[@]}"}
fi

echo "[release] Draft created: https://github.com/${GITHUB_REPO}/releases/tag/${TAG}"
