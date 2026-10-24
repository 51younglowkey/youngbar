#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
set -eu

version="${YOUNGBAR_VERSION:-0.1.0}"
asset="YoungBar-${version}.zip"
base="${YOUNGBAR_RELEASE_BASE:-https://github.com/51younglowkey/youngbar/releases/download/v${version}}"
app="$HOME/Applications/YoungBar.app"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$HOME/Applications"
echo "Downloading $asset ..."
curl -fL --retry 2 "$base/$asset" -o "$tmp/$asset"
curl -fsSL "$base/$asset.sha256" -o "$tmp/$asset.sha256"

expected="$(awk '{print $1}' "$tmp/$asset.sha256")"
actual="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
if [ "$expected" != "$actual" ]; then
    echo "Checksum mismatch: expected $expected, got $actual" >&2
    exit 1
fi

ditto -x -k "$tmp/$asset" "$tmp/out"
rm -rf "$app"
ditto "$tmp/out/YoungBar.app" "$app"
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
open "$app"

cat <<'TEXT'
YoungBar is installed at ~/Applications/YoungBar.app.

Next:
  1. Open the ••• menu or the gear in the strip, then Settings → 通用.
  2. Grant Device Control and Data Access (Accessibility) when prompted.
  3. Enable "登录时打开" if you want it at login.

YoungBar has no Dock icon; it lives in the menu bar.
TEXT
