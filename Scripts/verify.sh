#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."

sh Scripts/build.sh

APP="build/YoungBar.app"
test -x "$APP/Contents/MacOS/YoungBar"
test -f "$APP/Contents/Info.plist"
test -f "$APP/Contents/Resources/AppIcon.icns"
test -f "$APP/Contents/Resources/LICENSE"
test -f "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
test -f LICENSE
test -f THIRD_PARTY_NOTICES.md
test -f Vendor/LICENSE
grep -q "GPL-3.0-only" Sources/YoungBar/main.swift

# Localisation smoke check: every user-facing page should have both strings.
for pair in "布局:Layout" "外观:Appearance" "设置:Settings"; do
  zh=${pair%%:*}
  en=${pair##*:}
  grep -q "$zh" Sources/YoungBar/BarSettings.swift
  grep -q "$en" Sources/YoungBar/BarSettings.swift
done

echo "verify: build and bundle OK"
