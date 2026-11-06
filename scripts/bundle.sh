#!/bin/sh
# Release-builds Lax and wraps it as build/Lax.app, signed ad hoc so it runs locally.
set -e
cd "$(dirname "$0")/.."

swift build -c release --product Lax
bin_dir="$(swift build -c release --show-bin-path)"

app=build/Lax.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Lax" "$app/Contents/MacOS/Lax"
# SwiftPM resource bundles (e.g. LaxKit's emoji table); Bundle.module finds them here.
for resources in "$bin_dir"/*.bundle; do
    [ -e "$resources" ] && cp -R "$resources" "$app/Contents/Resources/"
done
cp Support/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $app"
