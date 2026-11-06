#!/bin/sh
# Release-builds Lax and wraps it as build/Lax.app, signed with the hardened runtime.
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
# CI passes a build number; local builds keep the one in Info.plist.
if [ -n "$BUILD_NUMBER" ]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$app/Contents/Info.plist"
fi
# The Liquid Glass icon (Icon Composer), compiled to Assets.car plus an .icns fallback.
xcrun actool Support/AppIcon.icon --compile "$app/Contents/Resources" --platform macosx \
    --minimum-deployment-target 27.0 --app-icon AppIcon \
    --output-partial-info-plist build/AppIcon-partial.plist > /dev/null
# A stable local certificate when there is one: the Keychain then recognises every build as
# the same app, instead of asking for access again after each ad-hoc-signed rebuild.
identity="Lax Local Code Signing"
if security find-certificate -c "$identity" > /dev/null 2>&1; then
    codesign --force --options runtime --sign "$identity" "$app"
else
    codesign --force --options runtime --sign - "$app"
fi
codesign --verify --strict "$app"

echo "Built $app"
