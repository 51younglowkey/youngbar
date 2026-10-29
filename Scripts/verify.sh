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
# The pages live in SettingsView.swift since the SwiftUI settings window.
for pair in "通用:General" "菜单栏:Menu Bar" "外观:Appearance" "快捷键:Shortcut"; do
  zh=${pair%%:*}
  en=${pair##*:}
  grep -q "$zh" Sources/YoungBar/SettingsView.swift
  grep -q "$en" Sources/YoungBar/SettingsView.swift
done

# Release builds carry no live self-tests.
if strings "$APP/Contents/MacOS/YoungBar" | grep -q 'YOUNGBAR_[A-Z]*TEST'; then
  echo "verify: test hooks found in the release binary" >&2
  exit 1
fi

echo "verify: build and bundle OK"
