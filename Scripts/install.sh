#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
set -eu

repo="${YOUNGBAR_REPO:-https://github.com/51younglowkey/youngbar.git}"
src="${YOUNGBAR_SRC:-$HOME/Applications/YoungBar-src}"
app="$HOME/Applications/YoungBar.app"

mkdir -p "$HOME/Applications"
if [ -d "$src/.git" ]; then
    git -C "$src" pull --ff-only
else
    rm -rf "$src"
    git clone --depth 1 "$repo" "$src"
fi

cd "$src"
sh Scripts/build.sh

rm -rf "$app"
ditto build/YoungBar.app "$app"
open "$app"

cat <<'TEXT'
YoungBar is installed at ~/Applications/YoungBar.app.

Next:
  1. Open the ••• menu or the gear in the strip, then Settings → 通用.
  2. Grant Device Control and Data Access (Accessibility) when prompted.
  3. Enable "登录时打开" if you want it at login.

YoungBar has no Dock icon; it lives in the menu bar.
TEXT
