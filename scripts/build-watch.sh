#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build/Payload build/Wristly.xcarchive build/Wristly-unsigned.ipa build/Wristly-watchsimulator.zip
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
ios_sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
if [[ ${ios_sdk_version%%.*} -lt 27 ]]; then
  echo "Requires iOS SDK >=27, found $ios_sdk_version. Select Xcode 27+." >&2
  exit 1
fi

xcodegen generate --spec project.yml | tee build/project-generation.log
swift test --parallel 2>&1 | tee build/swift-tests.log

# 1. Unsigned watchOS Simulator build (fast verification of WatchApp target).
xcodebuild -project Wristly.xcodeproj -scheme WristlyWatch \
  -configuration Debug -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build/DerivedData -resultBundlePath build/WatchBuild.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build 2>&1 | tee build/watch-build.log
sim_app=build/DerivedData/Build/Products/Debug-watchsimulator/WristlyWatch.app
test -d "$sim_app"
ditto -c -k --sequesterRsrc --keepParent "$sim_app" build/Wristly-watchsimulator.zip

# 2. Unsigned Release iOS + embedded Watch companion archive packaged as WatchBridge-ready IPA.
xcodebuild archive -project Wristly.xcodeproj -scheme Wristly \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Wristly.xcarchive \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee build/ios-archive.log

ios_app=build/Wristly.xcarchive/Products/Applications/Wristly.app
test -d "$ios_app"
find "$ios_app" -maxdepth 3 | tee build/ipa-contents.log

watch_embedded="$ios_app/Watch/WristlyWatch.app"
test -d "$watch_embedded"

# Verify WatchBridge / Apple companion bundle metadata.
ios_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ios_app/Info.plist")
watch_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$watch_embedded/Info.plist")
companion_id=$(/usr/libexec/PlistBuddy -c 'Print :WKCompanionAppBundleIdentifier' "$watch_embedded/Info.plist")
independent=$(/usr/libexec/PlistBuddy -c 'Print :WKRunsIndependentlyOfCompanionApp' "$watch_embedded/Info.plist")
echo "iOS ID=$ios_id Watch ID=$watch_id Companion ID=$companion_id Independent=$independent" | tee build/ipa-metadata.log
test "$ios_id" = "dev.wristly.app"
test "$watch_id" = "dev.wristly.app.watchkitapp"
test "$companion_id" = "$ios_id"
test "$independent" = "true"

mkdir -p build/Payload
cp -R "$ios_app" build/Payload/
(cd build && zip -9 -r Wristly-unsigned.ipa Payload) | tee build/ipa-zip.log
ls -lh build/Wristly-unsigned.ipa | tee -a build/ipa-metadata.log
