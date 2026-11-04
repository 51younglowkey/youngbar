#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
set -eu
cd "$(dirname "$0")/.."

app="${1:-build/YoungBar.app}"
identity="${YOUNGBAR_SIGN_IDENTITY:-}"
if [ -z "$identity" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "YoungBar Local Signing"; then
    identity="YoungBar Local Signing"
fi

if [ -n "$identity" ]; then
    echo "signing with identity: $identity"
    codesign --force --options runtime --sign "$identity" "$app"
elif [ "${YOUNGBAR_REQUIRE_IDENTITY:-0}" = "1" ]; then
    # A release signed ad-hoc is refused by every installed copy's updater,
    # and a user who installs it by hand is stuck with it: never fall back.
    echo "sign.sh: no signing identity (YoungBar Local Signing or YOUNGBAR_SIGN_IDENTITY); not signing ad-hoc for a release" >&2
    exit 1
else
    echo "signing ad-hoc (set YOUNGBAR_SIGN_IDENTITY for a stable identity)"
    codesign --force --sign - "$app"
fi

codesign --verify --deep --strict "$app"
codesign -dv --verbose=2 "$app" 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier' || true
