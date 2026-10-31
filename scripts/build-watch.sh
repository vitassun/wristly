#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
if ! command -v xcodebuild >/dev/null || ! command -v xcodegen >/dev/null; then
  echo 'Requires macOS, Xcode 27+ and XcodeGen 2.44.1+.' >&2
  exit 1
fi
xcodebuild -version | tee build/xcode-version.log
xcodebuild -showsdks | tee build/sdks.log
sdk_version=$(xcrun --sdk watchsimulator --show-sdk-version)
if [[ ${sdk_version%%.*} -lt 27 ]]; then
  echo "Requires watchOS Simulator SDK >=27, found $sdk_version. Select Xcode 27+." >&2
  exit 1
fi
xcodegen generate --spec project.yml | tee build/project-generation.log
swift test --parallel 2>&1 | tee build/swift-tests.log
xcodebuild -project Wristly.xcodeproj -scheme Wristly \
  -configuration Debug -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build/DerivedData -resultBundlePath build/WatchBuild.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | tee build/watch-build.log
app=build/DerivedData/Build/Products/Debug-watchsimulator/Wristly.app
test -d "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" build/Wristly-watchsimulator.zip
