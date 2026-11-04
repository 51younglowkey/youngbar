#!/bin/sh
# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only
#
# Every commit in a range must be by 51Young and carry no Claude attribution
# (AGENTS.md section 5). Usage: sh Scripts/check-commits.sh <revision range>
set -eu

range="${1:?usage: sh Scripts/check-commits.sh <revision range>}"
name="51Young"
email="193584257+51younglowkey@users.noreply.github.com"
attribution='^co-authored-by:.*(claude|anthropic)|^claude-session:|generated with .*claude code|claude\.ai/code/session|noreply@anthropic\.com'

# Listed first: a failure inside `for ... in $(...)` wouldn't stop the script,
# and a range git can't read would then pass as "0 commits".
commits="$(git rev-list "$range")"

checked=0
failed=0
for sha in $commits; do
    checked=$((checked + 1))
    author="$(git log -1 --format='%an <%ae>' "$sha")"
    author_name="$(git log -1 --format='%an' "$sha")"
    committer="$(git log -1 --format='%cn <%ce>' "$sha")"
    problems=""
    if [ "$committer" = "GitHub <noreply@github.com>" ]; then
        # A merge made on github.com: GitHub signs it and picks the author's
        # email itself, so only the name can be held to the rule.
        [ "$author_name" = "$name" ] || problems="$problems author: $author;"
    else
        [ "$author" = "$name <$email>" ] || problems="$problems author: $author;"
        [ "$committer" = "$name <$email>" ] || problems="$problems committer: $committer;"
    fi
    if git log -1 --format='%B' "$sha" | grep -Eiq "$attribution"; then
        problems="$problems Claude attribution in the message;"
    fi
    if [ -n "$problems" ]; then
        failed=$((failed + 1))
        echo "FAIL $(git log -1 --format='%h %s' "$sha")"
        echo "    $problems"
    fi
done

echo "$checked commit(s) checked in $range, $failed failed."
if [ "$failed" -ne 0 ]; then
    echo "Expected author and committer: $name <$email>, with no Claude trailers (AGENTS.md section 5)."
    exit 1
fi
