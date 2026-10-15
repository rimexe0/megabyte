#!/bin/sh
# Builds build/Megabyte.app (release, ad-hoc signed).
set -eu
cd "$(dirname "$0")/.."

swift build -c release
app=build/Megabyte.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Megabyte" "$app/Contents/MacOS/Megabyte"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"
echo "$app"
