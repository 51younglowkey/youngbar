#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
#
# Installs (or updates to) the latest YoungBar release:
#   curl -fsSL https://raw.githubusercontent.com/51younglowkey/youngbar/main/Scripts/install.sh | sh
# YOUNGBAR_VERSION=0.1.1 pins a version.
#
# Everything runs inside main(), called on the last line: a download cut
# off half-way through `curl | sh` defines nothing and runs nothing.
set -eu

main() {
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

    # Unpack and check the new app before anything already installed is touched.
    ditto -x -k "$tmp/$asset" "$tmp/out"
    new="$tmp/out/YoungBar.app"
    if [ ! -d "$new" ]; then
        echo "The download has no YoungBar.app in it; nothing was changed." >&2
        exit 1
    fi
    # The checksum comes from the same release, so it only proves the
    # download is complete. The signature says who built it.
    if ! codesign --verify --deep --strict "$new" 2>/dev/null; then
        echo "The downloaded app's signature is not valid; nothing was changed." >&2
        exit 1
    fi
    if codesign -dv "$new" 2>&1 | grep -q '^Signature=adhoc'; then
        echo "The downloaded app is not signed by its author (ad-hoc); nothing was changed." >&2
        exit 1
    fi
    # An installed copy signed by the author pins the certificate, as the
    # app's own updater does: a different signer is refused.
    if [ -d "$app" ] && ! codesign -dv "$app" 2>&1 | grep -q '^Signature=adhoc'; then
        requirement="$(codesign -d -r- "$app" 2>/dev/null | sed -n 's/^designated => //p')"
        if [ -n "$requirement" ] && ! codesign --verify -R="$requirement" "$new" 2>/dev/null; then
            echo "The downloaded app is signed by a different certificate than the installed one." >&2
            echo "Nothing was changed. If you trust this release, remove $app first and run this again." >&2
            exit 1
        fi
    fi

    # Quit this user's running copy the normal way: it shows every hidden
    # icon on quit.
    if pgrep -u "$(id -u)" -xq YoungBar; then
        osascript -e 'tell application id "studio.wuyiyang.youngbar" to quit' >/dev/null 2>&1 || true
        i=0
        while pgrep -u "$(id -u)" -xq YoungBar && [ $i -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
        if pgrep -u "$(id -u)" -xq YoungBar; then
            echo "YoungBar is still running. Quit it from the ••• menu and run this again." >&2
            exit 1
        fi
    fi

    mkdir -p "$dest"
    rm -rf "$app"
    ditto "$new" "$app"
    xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
    open "$app"

    cat <<TEXT
YoungBar $version is installed at $app.

Next:
  1. Allow Device Control and Data Access (Accessibility) when the guide asks.
  2. Choose icons to hide in Settings → Menu Bar, or open the strip and click them.
  3. Click ••• or press ⌘ twice to open the strip.

YoungBar has no Dock icon; it lives in the menu bar.
TEXT
}

main "$@"
