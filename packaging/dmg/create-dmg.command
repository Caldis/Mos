#!/usr/bin/env bash

# 创建 Mos 安装用的 DMG, 使用 create-dmg 脚本实现。
# Usage:
#   packaging/dmg/create-dmg.command [path-to-Mos.app]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ASSET_DIR="$SCRIPT_DIR/assets"
APP_PATH="${1:-$SCRIPT_DIR/Mos.app}"
APP_NAME="$(basename "$APP_PATH")"

[[ -d "$APP_PATH" ]] || {
  echo "找不到应用: $APP_PATH" >&2
  echo "请把 Mos.app 放在 packaging/dmg/ 下, 或传入 Mos.app 的路径。" >&2
  exit 1
}

command -v create-dmg >/dev/null 2>&1 || {
  echo "缺少 create-dmg, 请先安装: https://github.com/create-dmg/create-dmg" >&2
  exit 1
}

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
OUTPUT_DMG="$SCRIPT_DIR/Mos.${VERSION}.dmg"
TMP_DIR="$(mktemp -d -t mos-dmg.XXXXXX)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "开始构建 DMG..."

echo "清除遗留文件"
rm -f "$SCRIPT_DIR"/Mos.*.dmg

echo "生成 dmg-icon.png 对应的 icns 文件"
mkdir "$TMP_DIR/tmp.iconset"
cp "$ASSET_DIR/dmg-icon.png" "$TMP_DIR/tmp.iconset/icon_512x512@2x.png"
iconutil -c icns "$TMP_DIR/tmp.iconset" -o "$TMP_DIR/tmp.icns"

echo "创建 DMG"
create-dmg \
  --volname "Mos" \
  --volicon "$TMP_DIR/tmp.icns" \
  --background "$ASSET_DIR/dmg-bg.png" \
  --window-pos 200 120 \
  --window-size 700 400 \
  --icon-size 150 \
  --icon "$APP_NAME" 170 205 \
  --app-drop-link 535 195 \
  --hide-extension "$APP_NAME" \
  --no-internet-enable \
  "$OUTPUT_DMG" \
  "$APP_PATH"

echo "构建完成: $OUTPUT_DMG"
