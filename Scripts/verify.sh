#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

sh Scripts/build.sh

APP="build/YoungBar.app"
test -x "$APP/Contents/MacOS/YoungBar"
test -f "$APP/Contents/Info.plist"
test -f "$APP/Contents/Resources/AppIcon.icns"

# Localisation smoke check: every user-facing page should have both strings.
for pair in "布局:Layout" "外观:Appearance" "设置:Settings"; do
  zh=${pair%%:*}
  en=${pair##*:}
  grep -q "$zh" Sources/YoungBar/BarSettings.swift
  grep -q "$en" Sources/YoungBar/BarSettings.swift
done

echo "verify: build and bundle OK"
