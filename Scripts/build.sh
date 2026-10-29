#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
# --disable-sandbox: SwiftPM's own sandbox cannot nest inside a host sandbox
# (e.g. DSH). The package has no build plugins, so manifest sandboxing adds
# nothing here.
# TESTHOOKS=1 compiles the live self-tests (Sources/YoungBar/TestHooks.swift)
# in; release packages never set it.
if [ "${TESTHOOKS:-0}" = "1" ]; then
    swift build -c release --product YoungBar --disable-sandbox -Xswiftc -DYOUNGBAR_TESTHOOKS
else
    swift build -c release --product YoungBar --disable-sandbox
fi
app='build/YoungBar.app'
# Assemble and sign a fresh bundle, then swap it in. Overwriting the
# executable of a running YoungBar in place gets it killed with
# "Code Signature Invalid" (it pages in the new bytes), which skips the
# reveal-on-quit path.
staging='build/YoungBar.app.staging'
rm -rf "$staging"
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
cp .build/release/YoungBar "$staging/Contents/MacOS/YoungBar"
cp Info.plist "$staging/Contents/Info.plist"
cp Resources/AppIcon.icns "$staging/Contents/Resources/AppIcon.icns"
cp -f Resources/Theme-*.jpg "$staging/Contents/Resources/"
cp LICENSE "$staging/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$staging/Contents/Resources/THIRD_PARTY_NOTICES.md"
sh Scripts/sign.sh "$staging"
rm -rf "$app.old"
if [ -d "$app" ]; then mv "$app" "$app.old"; fi
mv "$staging" "$app"
rm -rf "$app.old"
echo "$PWD/$app"
