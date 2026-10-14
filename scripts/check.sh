#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift test
xcodebuild -project ios/Town.xcodeproj -scheme Town -sdk iphonesimulator -configuration Debug -derivedDataPath artifacts/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
./android/gradlew -p android :app:assembleDebug :app:testDebugUnitTest :app:lintDebug --max-workers=2
