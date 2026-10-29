#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
#
# Installs (or updates to) the latest YoungBar release:
#   curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | sh
# YOUNGBAR_VERSION=0.1.1 pins a version.
set -eu

repo="https://github.com/51younglowkey/youngbar"
version="${YOUNGBAR_VERSION:-}"
if [ -z "$version" ]; then
    # /releases/latest redirects to /releases/tag/v<version>.
    latest="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$repo/releases/latest")"
    version="${latest##*/v}"
fi
case "$version" in
    ''|*/*) echo "Could not find the latest YoungBar release." >&2; exit 1 ;;
esac

asset="YoungBar-${version}.zip"
base="${YOUNGBAR_RELEASE_BASE:-$repo/releases/download/v${version}}"
if [ -w /Applications ]; then dest=/Applications; else dest="$HOME/Applications"; fi
app="$dest/YoungBar.app"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading YoungBar $version ..."
curl -fL --retry 2 "$base/$asset" -o "$tmp/$asset"
curl -fsSL "$base/$asset.sha256" -o "$tmp/$asset.sha256"

expected="$(awk '{print $1}' "$tmp/$asset.sha256")"
actual="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
if [ "$expected" != "$actual" ]; then
    echo "Checksum mismatch: expected $expected, got $actual" >&2
    exit 1
fi

# Quit a running copy the normal way: it shows every hidden icon on quit.
if pgrep -xq YoungBar; then
    osascript -e 'tell application id "studio.wuyiyang.youngbar" to quit' >/dev/null 2>&1 || true
    i=0
    while pgrep -xq YoungBar && [ $i -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
fi

mkdir -p "$dest"
ditto -x -k "$tmp/$asset" "$tmp/out"
rm -rf "$app"
ditto "$tmp/out/YoungBar.app" "$app"
xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
open "$app"

cat <<TEXT
YoungBar $version is installed at $app.

Next:
  1. Allow Device Control and Data Access (Accessibility) when the guide asks.
  2. Choose icons to hide in Settings → Menu Bar.
  3. Click ••• or press ⌃⌥B to open the strip.

YoungBar has no Dock icon; it lives in the menu bar.
TEXT
