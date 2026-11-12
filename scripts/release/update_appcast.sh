#!/usr/bin/env bash
# update_appcast.sh - Sign zip and update appcast.xml
# Usage: update_appcast.sh <zip_path> <changelog_html_file> [--tag TAG]
# Reads signing key from macOS Keychain via Sparkle sign_update tool
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
BUILD_DIR="$ROOT_DIR/build"
RELEASE_DIR="$ROOT_DIR/release"
GITHUB_REPO="Caldis/Mos"

die() { echo "Error: $*" >&2; exit 1; }
info() { echo "[appcast] $*"; }

ZIP_PATH="${1:-}"
CHANGELOG_FILE="${2:-}"
TAG_OVERRIDE=""

shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG_OVERRIDE="$2"; shift 2 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -n "$ZIP_PATH" && -f "$ZIP_PATH" ]] || die "Usage: update_appcast.sh <zip_path> <changelog_html_file> [--tag TAG]"
[[ -n "$CHANGELOG_FILE" && -f "$CHANGELOG_FILE" ]] || die "Changelog HTML file required"

# Find Sparkle sign_update tool (scoped to Mos project DerivedData)
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData/Mos-* -path "*/artifacts/sparkle/Sparkle/bin/sign_update" 2>/dev/null | head -1)
[[ -n "$SIGN_UPDATE" ]] || SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -not -path "*/old_dsa_scripts/*" -not -path "*/checkouts/*" 2>/dev/null | head -1)
[[ -n "$SIGN_UPDATE" ]] || die "Sparkle sign_update not found. Build the project in Xcode first."

# Sign the zip (reads EdDSA key from Keychain)
SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH" 2>&1) || die "Signing failed. Import key first: generate_keys -f <key_file>"

ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//')
FILE_LENGTH=$(echo "$SIGN_OUTPUT" | grep -o 'length="[^"]*"' | sed 's/length="//;s/"//')

[[ -n "$ED_SIGNATURE" ]] || die "Failed to parse edSignature from sign_update output"
[[ -n "$FILE_LENGTH" ]] || FILE_LENGTH=$(wc -c < "$ZIP_PATH" | tr -d '[:space:]')

# Read version from zip's Info.plist
VERSION_JSON=$(python3 - "$ZIP_PATH" <<'PY'
import json, plistlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    candidates = [n for n in z.namelist() if n.endswith(".app/Contents/Info.plist")]
    if not candidates: raise SystemExit("No Info.plist in zip")
    # Prefer shortest path (root app plist, not nested framework plists)
    candidates.sort(key=len)
    plist = plistlib.loads(z.read(candidates[0]))
    print(json.dumps({
        "short": plist.get("CFBundleShortVersionString", ""),
        "build": plist.get("CFBundleVersion", ""),
    }))
PY
)
SHORT_VERSION=$(echo "$VERSION_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['short'])")
BUNDLE_VERSION=$(echo "$VERSION_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['build'])")

ZIP_NAME=$(basename "$ZIP_PATH")
TAG="${TAG_OVERRIDE:-$SHORT_VERSION}"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ZIP_NAME}"
PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S %z")
CHANGELOG_HTML=$(cat "$CHANGELOG_FILE")

# Detect channel from zip name
CHANNEL_ELEMENT=""
ENCLOSURE_CHANNEL=""
if [[ "$ZIP_NAME" == *"-beta-"* ]]; then
  CHANNEL_ELEMENT=$'\n      <sparkle:channel>beta</sparkle:channel>'
  ENCLOSURE_CHANNEL=$'\n        sparkle:channel="beta"'
elif [[ "$ZIP_NAME" == *"-alpha-"* ]]; then
  CHANNEL_ELEMENT=$'\n      <sparkle:channel>alpha</sparkle:channel>'
  ENCLOSURE_CHANNEL=$'\n        sparkle:channel="alpha"'
fi

# Build new <item>
NEW_ITEM=$(cat <<EOF
    <item>
      <title>Mos ${SHORT_VERSION}</title>
${CHANNEL_ELEMENT}
      <description><![CDATA[${CHANGELOG_HTML}]]></description>
      <pubDate>${PUB_DATE}</pubDate>

      <enclosure
        url="${DOWNLOAD_URL}"
        length="${FILE_LENGTH}"
        type="application/octet-stream"
        sparkle:shortVersionString="${SHORT_VERSION}"
        sparkle:version="${BUNDLE_VERSION}"
        sparkle:edSignature="${ED_SIGNATURE}"${ENCLOSURE_CHANNEL}
      />
    </item>
EOF
)

# Merge into existing appcast (prepend new item, dedup by version)
APPCAST_BUILD="$BUILD_DIR/appcast.xml"
APPCAST_RELEASE="$RELEASE_DIR/appcast.xml"

BASE_APPCAST=""
[[ -s "$APPCAST_RELEASE" ]] && BASE_APPCAST="$APPCAST_RELEASE"
[[ -z "$BASE_APPCAST" && -s "$APPCAST_BUILD" ]] && BASE_APPCAST="$APPCAST_BUILD"

APPCAST_XML=$(NEW_ITEM="$NEW_ITEM" python3 - "$BASE_APPCAST" "$BUNDLE_VERSION" <<'PY'
import os, re, sys

base_path = sys.argv[1].strip()
new_version = sys.argv[2].strip()
new_item = os.environ.get("NEW_ITEM", "").strip()

DEFAULT = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
    xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
    xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Mos</title>
    <link>https://mos.caldis.me/</link>
    <description>Mos Updates</description>
    <language>en</language>
  </channel>
</rss>
"""

text = open(base_path, "r").read() if base_path and os.path.exists(base_path) else DEFAULT
item_re = re.compile(r"<item\b.*?</item>", flags=re.S)
matches = list(item_re.finditer(text))

if matches:
    prefix = text[:matches[0].start()]
    suffix = text[matches[-1].end():]
    items = [m.group(0) for m in matches]
else:
    insert_at = text.rfind("</channel>")
    if insert_at == -1:
        text = DEFAULT
        insert_at = text.rfind("</channel>")
    prefix = text[:insert_at]
    suffix = text[insert_at:]
    items = []

def extract_version(item):
    m = re.search(r'sparkle:version="([^"]+)"', item)
    return m.group(1) if m else ""

filtered = []
seen = set()
for item in items:
    v = extract_version(item)
    if v == new_version or v in seen:
        continue
    if v: seen.add(v)
    filtered.append(item)

all_items = [new_item] + filtered
sep = "\n\n    "
out = prefix + sep.join(i.strip() for i in all_items if i.strip()) + suffix
sys.stdout.write(out if out.endswith("\n") else out + "\n")
PY
)

mkdir -p "$BUILD_DIR" "$RELEASE_DIR"
printf '%s' "$APPCAST_XML" > "$APPCAST_BUILD"
cp "$APPCAST_BUILD" "$APPCAST_RELEASE"

info "Signed:    $ZIP_NAME"
info "Signature: ${ED_SIGNATURE:0:20}..."
info "Tag:       $TAG"
info "URL:       $DOWNLOAD_URL"
info "Wrote:     $APPCAST_BUILD"
info "Copied:    $APPCAST_RELEASE"
