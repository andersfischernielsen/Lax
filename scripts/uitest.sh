#!/bin/sh
# Runs Lax's UI tests against the fixture workspace. They drive the real mouse and keyboard
# while they run, so leave the Mac alone until they finish.
set -e
cd "$(dirname "$0")/.."
xcodebuild test -project Lax.xcodeproj -scheme "Lax App" -destination 'platform=macOS' \
    -derivedDataPath build/DerivedData "$@"
