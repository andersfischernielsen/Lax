#!/bin/sh
# Runs `swift test`. With only the Command Line Tools installed, SwiftPM doesn't
# pass Swift Testing's macro plugin to the compiler, so point at it explicitly.
set -e
cd "$(dirname "$0")/.."

plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
    set -- -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
