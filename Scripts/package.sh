#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."

# A release must carry the author's certificate: installed copies only accept
# an update signed like themselves. YOUNGBAR_ALLOW_ADHOC=1 packages a test
# build anyway (never publish that one).
if [ "${YOUNGBAR_ALLOW_ADHOC:-0}" = "1" ]; then
    TESTHOOKS=0 sh Scripts/build.sh
else
    TESTHOOKS=0 YOUNGBAR_REQUIRE_IDENTITY=1 sh Scripts/build.sh
    if codesign -dv build/YoungBar.app 2>&1 | grep -q '^Signature=adhoc'; then
        echo "package.sh: build/YoungBar.app is signed ad-hoc; not packaging it" >&2
        exit 1
    fi
fi
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
out="dist/YoungBar-$version"
mkdir -p dist
rm -f "$out.zip" "$out.zip.sha256"
ditto -c -k --keepParent build/YoungBar.app "$out.zip"
(cd dist && shasum -a 256 "YoungBar-$version.zip" > "YoungBar-$version.zip.sha256")
echo "$PWD/$out.zip"
cat "$out.zip.sha256"
