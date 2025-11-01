#!/bin/bash

# 创建 mos 安装用的 dmg, 使用 create-dmg 脚本实现
# 先安装 https://github.com/create-dmg/create-dmg
# 然后东西都丢到 Mos 的 dmg 目录下
# - dmg-bg.png DMG 的背景图, 分辨率 700x400
# - dmg-icon.png DMG 的图标, 分辨率 1204*1024
# - Mos, 应用本体

# 设置变量
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "Mos.app/Contents/Info.plist")

echo "开始构建 DMG..."

echo "清除遗留文件"
rm -f Mos.*.dmg

echo "生成 dmg-icon.png 对应的 icns 文件"
mkdir tmp.iconset && cp dmg-icon.png tmp.iconset/icon_512x512@2x.png && iconutil -c icns tmp.iconset -o tmp.icns && rm -rf tmp.iconset

echo "创建 DMG"
create-dmg \
  --volname "Mos" \
  --volicon "tmp.icns" \
  --background "dmg-bg.png" \
  --window-pos 200 120 \
  --window-size 700 400 \
  --icon-size 150 \
  --icon "Mos.app" 170 205 \
  --app-drop-link 535 195 \
  --hide-extension "Mos.app" \
  --no-internet-enable \
  "Mos.${VERSION}.dmg" \
  "Mos.app"

echo "删除临时创建的图标"
rm -f tmp.icns

echo "构建完成"