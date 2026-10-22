#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
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
cp LICENSE "$app/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
codesign --force --sign - --timestamp=none "$app"
echo "$PWD/$app"
