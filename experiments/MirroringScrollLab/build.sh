#!/bin/zsh
# Generates the Xcode project, builds a signed Debug app and opens it.
set -e
cd ${0:A:h}
xcodegen generate >/dev/null
xcodebuild -project MirroringScrollLab.xcodeproj -scheme MirroringScrollLab -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath DerivedData -allowProvisioningUpdates build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
[[ "${1:-}" == "--no-open" ]] || open DerivedData/Build/Products/Debug/MirroringScrollLab.app
