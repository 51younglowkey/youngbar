#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# --disable-sandbox: SwiftPM's own sandbox cannot nest inside a host sandbox
# (e.g. DSH). The package has no build plugins, so manifest sandboxing adds
# nothing here.
swift build -c release --product YoungBar --disable-sandbox
app='build/YoungBar.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/YoungBar "$app/Contents/MacOS/YoungBar"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -f Resources/Theme-*.jpg "$app/Contents/Resources/"
codesign --force --sign - --timestamp=none "$app"
echo "$PWD/$app"
