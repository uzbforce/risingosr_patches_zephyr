#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Apply every patch in patches/ to a RisingOS Revived checkout. The layout of
# patches/ mirrors the checkout, so a patch at patches/a/b/foo.patch applies
# inside $ANDROID_BUILD_TOP/a/b.
#
# Usage: ./apply.sh [checkout-root]

set -u

root="${1:-${ANDROID_BUILD_TOP:-$PWD}}"
repo_root="$(cd "$(dirname "$0")" && pwd)/patches"

if [ ! -d "$repo_root" ]; then
    echo "no patches/ directory next to $0" >&2
    exit 1
fi

if [ ! -d "$root/build/make" ]; then
    echo "$root does not look like a ROM checkout (no build/make)" >&2
    exit 1
fi

applied=0
skipped=0
failed=0

while IFS= read -r patch; do
    rel="${patch#"$repo_root"/}"
    project="${rel%/*}"
    [ "$project" = "$rel" ] && project="."   # patch at the repo root
    dir="$root/$project"

    printf '%-78s ' "$project/${rel##*/}"

    if [ ! -d "$dir" ]; then
        echo "SKIP (no such project in this checkout)"
        skipped=$((skipped + 1))
        continue
    fi

    if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        echo "SKIP (not a git checkout)"
        skipped=$((skipped + 1))
        continue
    fi

    # Already there? Then applying it again is a no-op.
    if git -C "$dir" apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "already applied"
        skipped=$((skipped + 1))
        continue
    fi

    if git -C "$dir" apply --check "$patch" >/dev/null 2>&1; then
        git -C "$dir" apply "$patch" && echo "applied"
        applied=$((applied + 1))
        continue
    fi

    # RisingOS' copies of some AOSP projects carry small local differences in
    # neighbouring lines; a one-line context reduction still pins the change to
    # the intended hunk.
    if git -C "$dir" apply -C1 --check "$patch" >/dev/null 2>&1; then
        git -C "$dir" apply -C1 "$patch" && echo "applied (-C1)"
        applied=$((applied + 1))
        continue
    fi

    echo "FAILED (does not apply cleanly)"
    git -C "$dir" apply -C1 --check "$patch" 2>&1 | sed 's/^/    /'
    failed=$((failed + 1))
done < <(find "$repo_root" -type f -name '*.patch' | sort)

echo
echo "applied $applied, skipped $skipped, failed $failed"
echo "changes are unstaged: review with 'git -C $root/<project> diff'"

[ "$failed" -eq 0 ]
