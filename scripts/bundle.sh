#!/bin/sh
# Release-builds Lax and wraps it as build/Lax.app, signed ad hoc so it runs locally.
set -e
cd "$(dirname "$0")/.."

swift build -c release --product Lax
bin="$(swift build -c release --show-bin-path)/Lax"

app=build/Lax.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Lax"
cp Support/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $app"
