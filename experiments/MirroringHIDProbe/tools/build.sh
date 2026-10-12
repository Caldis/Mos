#!/bin/zsh
# 把辅助工具构建到 tools/.build, 把探针 App 构建到 ../DerivedData
set -e
T=${0:A:h}; mkdir -p $T/.build
swiftc -O $T/winctl.swift -o $T/.build/winctl
swiftc -O $T/evspy.swift -o $T/.build/evspy
cd $T/.. && xcodegen generate >/dev/null
xcodebuild -project MirroringHIDProbe.xcodeproj -scheme MirroringHIDProbe -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData -allowProvisioningUpdates build | grep -E "error|BUILD (SUCCEEDED|FAILED)"
