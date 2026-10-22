#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."

sh Scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
out="dist/YoungBar-$version"
mkdir -p dist
rm -f "$out.zip" "$out.zip.sha256"
ditto -c -k --keepParent build/YoungBar.app "$out.zip"
shasum -a 256 "$out.zip" > "$out.zip.sha256"
echo "$PWD/$out.zip"
cat "$out.zip.sha256"
