#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DOCS_DIR="$ROOT_DIR/docs"
KEY_FILE="$ROOT_DIR/sparkle_private_key.txt"

GITHUB_REPO="Caldis/Mos"
RELEASES_BASE_URL="https://github.com/${GITHUB_REPO}/releases"
RELEASE_NOTES_BASE_URL="${RELEASE_NOTES_BASE_URL:-https://mos.caldis.me/release-notes}"
SINCE_COMMIT="${RELEASE_NOTES_SINCE_COMMIT:-}"

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "[appcast] $*"
}

need_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi

  case "$cmd" in
    git)
      die "Missing dependency: 'git' (install Xcode Command Line Tools: 'xcode-select --install')"
      ;;
    python3)
      die "Missing dependency: 'python3' (install Xcode Command Line Tools: 'xcode-select --install', or install Python 3)"
      ;;
    openssl)
      die "Missing dependency: 'openssl' (recommended: 'brew install openssl@3' and ensure it's in PATH)"
      ;;
    *)
      die "Missing dependency: '$cmd'"
      ;;
  esac
}

need_cmd python3
need_cmd openssl

[[ -d "$BUILD_DIR" ]] || die "Missing build directory: $BUILD_DIR"
[[ -d "$DOCS_DIR" ]] || die "Missing docs directory: $DOCS_DIR"
[[ -f "$KEY_FILE" ]] || die "Missing Sparkle private key file: $KEY_FILE"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since|--since-commit)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      SINCE_COMMIT="$2"
      shift 2
      ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") --since <commit>

Options:
  --since, --since-commit   Git commit to generate release notes from (exclusive)

Env:
  RELEASE_NOTES_SINCE_COMMIT  Same as --since
EOF
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -z "$SINCE_COMMIT" ]]; then
  cat >&2 <<EOF
Missing required parameter: --since <commit>

Example:
  $(basename "$0") --since 1e07d2f
EOF
  exit 1
fi

ZIP_PATH="$(
  python3 - "$BUILD_DIR" <<'PY'
import os, sys
build_dir = sys.argv[1]
zips = []
for name in os.listdir(build_dir):
    if name.lower().endswith(".zip"):
        path = os.path.join(build_dir, name)
        if os.path.isfile(path):
            zips.append(path)
if not zips:
    sys.exit(2)
zips.sort(key=lambda p: os.stat(p).st_mtime, reverse=True)
print(zips[0])
PY
)" || {
  cat >&2 <<EOF
No zip found in: $BUILD_DIR

Please archive + notarize Mos.app, then zip it and place it into $BUILD_DIR.

Expected filename:
  Mos.Versions.<version>{-beta}-<YYYYMMDD>.<num>.zip

Examples:
  Mos.Versions.4.0.0-20260108.1.zip
  Mos.Versions.4.0.0-beta-20260108.1.zip
EOF
  exit 1
}

ZIP_FILE="$(basename "$ZIP_PATH")"

parse_json="$(
  python3 - "$ZIP_FILE" <<'PY'
import json, re, sys
name = sys.argv[1]
pattern = re.compile(r"^Mos\.Versions\.(?P<version>\d+\.\d+\.\d+)(?P<beta>-beta)?-(?P<date>\d{8})\.(?P<num>\d+)\.zip$")
m = pattern.match(name)
if not m:
    print(json.dumps({"ok": False}))
    sys.exit(0)
print(json.dumps({
    "ok": True,
    "version": m.group("version"),
    "beta": bool(m.group("beta")),
    "date": m.group("date"),
    "num": m.group("num"),
}))
PY
)"

if [[ "$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("ok"))' <<<"$parse_json")" != "True" ]]; then
  cat >&2 <<EOF
Invalid zip filename:
  $ZIP_FILE

Expected filename:
  Mos.Versions.<version>{-beta}-<YYYYMMDD>.<num>.zip

Examples:
  Mos.Versions.4.0.0-20260108.1.zip
  Mos.Versions.4.0.0-beta-20260108.1.zip
EOF
  exit 1
fi

VERSION="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["version"])' <<<"$parse_json")"
BETA_FLAG="$(python3 -c 'import json,sys; print("true" if json.loads(sys.stdin.read())["beta"] else "false")' <<<"$parse_json")"
DATE_PART="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["date"])' <<<"$parse_json")"
NUM_PART="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["num"])' <<<"$parse_json")"

TAG="${VERSION}"
if [[ "$BETA_FLAG" == "true" ]]; then
  TAG="${TAG}-beta"
fi
TAG="${TAG}-${DATE_PART}.${NUM_PART}"

DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${ZIP_FILE}"
FILE_LENGTH="$(wc -c <"$ZIP_PATH" | tr -d '[:space:]')"
PUB_DATE="$(date -u "+%a, %d %b %Y %H:%M:%S %z")"

read_plist_json="$(
  python3 - "$ZIP_PATH" <<'PY'
import json, plistlib, sys, zipfile
zip_path = sys.argv[1]
with zipfile.ZipFile(zip_path) as z:
    try:
        data = z.read("Mos.app/Contents/Info.plist")
    except KeyError:
        candidates = [n for n in z.namelist() if n.endswith(".app/Contents/Info.plist")]
        if not candidates:
            raise SystemExit("Missing *.app/Contents/Info.plist in zip")
        data = z.read(candidates[0])
plist = plistlib.loads(data)
print(json.dumps({
    "CFBundleShortVersionString": plist.get("CFBundleShortVersionString", ""),
    "CFBundleVersion": plist.get("CFBundleVersion", ""),
}))
PY
)"

SHORT_VERSION="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("CFBundleShortVersionString",""))' <<<"$read_plist_json")"
BUNDLE_VERSION="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("CFBundleVersion",""))' <<<"$read_plist_json")"

[[ -n "$SHORT_VERSION" ]] || die "Failed to read CFBundleShortVersionString from zip Info.plist"
[[ -n "$BUNDLE_VERSION" ]] || die "Failed to read CFBundleVersion from zip Info.plist"

need_cmd git
git rev-parse --verify "${SINCE_COMMIT}^{commit}" >/dev/null 2>&1 || die "Invalid commit: $SINCE_COMMIT"

commit_shas="$(git log "${SINCE_COMMIT}..HEAD" --no-merges --reverse --pretty=format:%H)"

python_code="$(
  cat <<'PY'
import html
import os
import re
import subprocess
import sys

since_commit = sys.argv[1]
is_beta = sys.argv[2].lower() == "true"
commits = [c.strip() for c in os.environ.get("COMMITS", "").splitlines() if c.strip()]

def sh(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()

def subject_for_commit(commit: str) -> str:
    return sh("git", "show", "-s", "--format=%s", commit)

def files_for_commit(commit: str) -> list[str]:
    out = sh("git", "show", "--name-only", "--pretty=format:", commit)
    return [l.strip() for l in out.splitlines() if l.strip()]

def diff_for_commit(commit: str) -> str:
    try:
        return sh("git", "show", "--pretty=format:", "--unified=0", commit)
    except Exception:
        return ""

def is_user_visible(paths: list[str]) -> bool:
    return any(p.startswith("Mos/") or p.startswith("Mos.xcodeproj/") for p in paths)

def normalize_subject(s: str) -> str:
    s = s.strip()
    s = re.sub(r"^(fix|feat|chore|docs|refactor|perf|style|test)(\\([^)]*\\))?:\\s*", "", s, flags=re.I)
    return (s[0:1].upper() + s[1:]) if s else s

items: dict[str, dict[str, tuple[str, str]]] = {
    "feature": {},
    "improvement": {},
    "fix": {},
}

def add(cat: str, key: str, zh: str, en: str) -> None:
    items[cat][key] = (zh, en)

for commit in commits:
    paths = files_for_commit(commit)
    if not is_user_visible(paths):
        continue

    subj = normalize_subject(subject_for_commit(commit))
    subj_l = subj.lower()
    diff = diff_for_commit(commit)
    diff_l = diff.lower()
    paths_join = "\n".join(paths).lower()

    # Sparkle / updates integration
    if ("sparkle" in paths_join) or ("spustandardupdatercontroller" in diff_l) or ("sufe edurl".replace(" ", "") in diff_l) or ("supublicedkey" in diff_l):
        add(
            "feature",
            "sparkle-updates",
            "新增应用内更新检查（Sparkle），并支持 Beta 渠道开关。",
            "Added in-app update checking via Sparkle, with an optional beta channel toggle.",
        )
        continue

    # Localization improvements
    if any((".xcstrings" in p) or (".lproj/" in p) for p in paths) or "translation" in subj_l:
        if "french" in subj_l or any("/fr" in p for p in paths):
            add("improvement", "l10n-fr", "更新法语本地化翻译。", "Updated French localization.")
        else:
            add("improvement", "l10n", "更新本地化翻译。", "Updated localization.")
        continue

    # Middle mouse mapping fix
    if ("middle mouse" in subj_l) or ("middle" in subj_l and "mouse" in subj_l) or ("keycode" in paths_join and "middle" in diff_l):
        add(
            "fix",
            "middle-mouse",
            "允许在不按修饰键的情况下绑定鼠标中键。",
            "Allowed binding the middle mouse button without modifier keys.",
        )
        continue

    # Shortcut / keyboard layout fixes
    if ("shortcut" in subj_l or "keyboard" in subj_l or "layout" in subj_l) or ("/shortcut/" in paths_join):
        add(
            "fix",
            "shortcut-layout",
            "修复部分非 US 键盘布局下的快捷键问题。",
            "Fixed some shortcut issues on non‑US keyboard layouts.",
        )
        continue

    # Generic fallback categorization
    if subj_l.startswith("fix") or "fix" in subj_l or "bug" in subj_l:
        add("fix", f"commit-{commit[:7]}", f"修复：{subj}", f"Fix: {subj}")
    elif subj_l.startswith("add") or "add" in subj_l or "new" in subj_l:
        add("feature", f"commit-{commit[:7]}", f"新增：{subj}", f"New: {subj}")
    else:
        add("improvement", f"commit-{commit[:7]}", f"改进：{subj}", f"Improved: {subj}")

def render_section(title: str, bullets: list[str]) -> str:
    if not bullets:
        return ""
    li = "".join(f"<li>{html.escape(b)}</li>" for b in bullets)
    return f"<h2>{html.escape(title)}</h2>\n<ul>{li}</ul>\n\n"

def render_lang(titles: dict[str, str], use_zh: bool) -> str:
    parts: list[str] = []
    for cat in ("feature", "improvement", "fix"):
        bullets = [(zh if use_zh else en) for (zh, en) in items[cat].values()]
        section = render_section(titles[cat], bullets)
        if section:
            parts.append(section)
    if not parts:
        parts.append("<p>No changes.</p>")
    return "".join(parts)

zh_html = render_lang({"feature": "新功能", "improvement": "改进", "fix": "修复"}, True)
en_html = render_lang({"feature": "New Feature", "improvement": "Improvements", "fix": "Fixes"}, False)

body = zh_html + "\n<hr/>\n\n" + en_html
body = body.replace("]]>", "]]&gt;")
print(body)
PY
)"

RELEASE_NOTES_HTML="$(COMMITS="$commit_shas" python3 -c "$python_code" "$SINCE_COMMIT" "$BETA_FLAG")"

# Generate two hosted release notes pages (Chinese + English).
RELEASE_NOTES_DIR_BUILD="$BUILD_DIR/release-notes"
RELEASE_NOTES_DIR_DOCS="$DOCS_DIR/release-notes"
mkdir -p "$RELEASE_NOTES_DIR_BUILD" "$RELEASE_NOTES_DIR_DOCS"

NOTES_ZH_BUILD_DEFAULT="$RELEASE_NOTES_DIR_BUILD/${TAG}.zh.html"
NOTES_EN_BUILD_DEFAULT="$RELEASE_NOTES_DIR_BUILD/${TAG}.en.html"
NOTES_ZH_BUILD="${RELEASE_NOTES_ZH_FILE:-$NOTES_ZH_BUILD_DEFAULT}"
NOTES_EN_BUILD="${RELEASE_NOTES_EN_FILE:-$NOTES_EN_BUILD_DEFAULT}"

if [[ ! -s "$NOTES_ZH_BUILD" || ! -s "$NOTES_EN_BUILD" ]]; then
  # Split bilingual HTML into two pages following the same structure, but language-specific.
  NOTES_HTML="$RELEASE_NOTES_HTML" python3 -c '
import os
import sys

zh_out = sys.argv[1]
en_out = sys.argv[2]

content = os.environ.get("NOTES_HTML", "")
parts = content.split("<hr/>")
zh_body = parts[0].strip()
en_body = parts[1].strip() if len(parts) > 1 else ""

def wrap_page(body: str, lang: str) -> str:
    return (
        "<!doctype html>\n"
        f"<html lang=\"{lang}\">\n"
        "<head>\n"
        "  <meta charset=\"utf-8\" />\n"
        "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n"
        "  <title>Mos Release Notes</title>\n"
        "  <style>\n"
        "    body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif;line-height:1.5;padding:20px;max-width:900px;margin:0 auto;}\n"
        "    h2{margin:18px 0 8px 0;}\n"
        "    ul{margin:6px 0 14px 18px;}\n"
        "    code{background:#f3f4f6;padding:0 4px;border-radius:4px;}\n"
        "    a{color:#2563eb;text-decoration:none;}\n"
        "    a:hover{text-decoration:underline;}\n"
        "  </style>\n"
        "</head>\n"
        "<body>\n"
        f"{body}\n"
        "</body>\n"
        "</html>\n"
    )

with open(zh_out, "w", encoding="utf-8") as f:
    f.write(wrap_page(zh_body, "zh"))
with open(en_out, "w", encoding="utf-8") as f:
    f.write(wrap_page(en_body, "en"))
' "$NOTES_ZH_BUILD" "$NOTES_EN_BUILD"
fi

# Copy release notes into docs for publishing
cp "$NOTES_ZH_BUILD" "$RELEASE_NOTES_DIR_DOCS/$(basename "$NOTES_ZH_BUILD")"
cp "$NOTES_EN_BUILD" "$RELEASE_NOTES_DIR_DOCS/$(basename "$NOTES_EN_BUILD")"

RELEASE_NOTES_ZH_URL="${RELEASE_NOTES_BASE_URL}/$(basename "$NOTES_ZH_BUILD")"
RELEASE_NOTES_EN_URL="${RELEASE_NOTES_BASE_URL}/$(basename "$NOTES_EN_BUILD")"

key_b64="$(tr -d '\n\r ' <"$KEY_FILE")"
[[ -n "$key_b64" ]] || die "Sparkle private key file is empty: $KEY_FILE"

tmp_dir="$(mktemp -d /tmp/mos_appcast.XXXXXX)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

key_der="$tmp_dir/key.der"
key_pem="$tmp_dir/key.pem"
pub_pem="$tmp_dir/pub.pem"
sig_bin="$tmp_dir/sig.bin"

python3 - "$key_b64" "$key_der" <<'PY'
import base64, sys
seed_b64, out_path = sys.argv[1], sys.argv[2]
seed = base64.b64decode(seed_b64)
if len(seed) != 32:
    raise SystemExit(f"Expected 32-byte Ed25519 seed, got {len(seed)} bytes")
der_prefix = bytes.fromhex("302e020100300506032b657004220420")
open(out_path, "wb").write(der_prefix + seed)
PY

if ! openssl pkey -inform DER -in "$key_der" -out "$key_pem" >/dev/null 2>&1; then
  cat >&2 <<EOF
OpenSSL does not support importing Ed25519 keys on this machine.

Fix:
  - Install a modern OpenSSL (e.g. Homebrew 'openssl@3')
  - Ensure your PATH points to it, then re-run this script
EOF
  exit 1
fi

openssl pkey -in "$key_pem" -pubout -out "$pub_pem" >/dev/null 2>&1
openssl dgst -binary -sign "$key_pem" -out "$sig_bin" "$ZIP_PATH" >/dev/null 2>&1
openssl pkeyutl -verify -pubin -inkey "$pub_pem" -sigfile "$sig_bin" -rawin -in "$ZIP_PATH" >/dev/null 2>&1
ED_SIGNATURE="$(openssl base64 -A -in "$sig_bin")"

APPCAST_BUILD="$BUILD_DIR/appcast.xml"
APPCAST_DOCS="$DOCS_DIR/appcast.xml"

item_attrs=""
channel_element=""
enclosure_channel_attr=""
if [[ "$BETA_FLAG" == "true" ]]; then
  # Sparkle channel filtering is easiest/most compatible when the channel is declared explicitly.
  channel_element=$'\n      <sparkle:channel>beta</sparkle:channel>'
  enclosure_channel_attr=$'\n        sparkle:channel="beta"'
fi

description_block=$'\n      <description><![CDATA['"$RELEASE_NOTES_HTML"$']]></description>'
release_notes_link_block=$'\n      <sparkle:releaseNotesLink xml:lang="zh">'${RELEASE_NOTES_ZH_URL}$'</sparkle:releaseNotesLink>\n      <sparkle:releaseNotesLink>'${RELEASE_NOTES_EN_URL}$'</sparkle:releaseNotesLink>'

cat >"$APPCAST_BUILD" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
    xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
    xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Mos</title>
    <link>https://mos.caldis.me/</link>
    <description>Mos Updates</description>
    <language>en</language>

    <item${item_attrs}>
      <title>Mos ${SHORT_VERSION}</title>
${channel_element}
${description_block}
      <pubDate>${PUB_DATE}</pubDate>
${release_notes_link_block}
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${FILE_LENGTH}"
        type="application/octet-stream"
        sparkle:shortVersionString="${SHORT_VERSION}"
        sparkle:version="${BUNDLE_VERSION}"
        sparkle:edSignature="${ED_SIGNATURE}"${enclosure_channel_attr}
      />
    </item>
  </channel>
</rss>
EOF

cp "$APPCAST_BUILD" "$APPCAST_DOCS"

info "Selected zip: $ZIP_PATH"
info "Release tag:  $TAG"
info "Download URL: $DOWNLOAD_URL"
info "Wrote:        $APPCAST_BUILD"
info "Copied:       $APPCAST_DOCS"
info "Done"
