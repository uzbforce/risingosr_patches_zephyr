#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Capture the change you made in a ROM project as a patch in this repo.
#
# Usage: ./capture.sh <project-path> "<subject>"
#   e.g. ./capture.sh hardware/qcom-caf/common "fix the bengal pickup"

set -eu

if [ $# -lt 2 ]; then
    sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

project="$1"
subject="$2"
root="${ANDROID_BUILD_TOP:-$PWD}"
repo_root="$(cd "$(dirname "$0")" && pwd)"
dir="$root/$project"

[ -d "$dir" ] || { echo "no such project: $dir" >&2; exit 1; }
git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || { echo "$dir is not a git checkout" >&2; exit 1; }

# Untracked files are part of the change - a new source file is often the whole
# point of it - but `git diff HEAD` cannot see them, so they have to be marked
# intent-to-add first. Only those exact paths are touched and the marker is
# removed again on the way out, so anything the caller had staged stays staged.
untracked=()
while IFS= read -r f; do
    [ -n "$f" ] && untracked+=("$f")
done < <(git -C "$dir" ls-files --others --exclude-standard)

restore_index() {
    local f
    for f in "${untracked[@]+\"${untracked[@]}\"}"; do
        git -C "$dir" reset -q -- "$f" 2>/dev/null || true
    done
}
trap restore_index EXIT

for f in "${untracked[@]+\"${untracked[@]}\"}"; do
    git -C "$dir" add -N -- "$f"
done

if git -C "$dir" diff HEAD --quiet; then
    echo "nothing to capture in $project (working tree clean)" >&2
    exit 1
fi

# Next free number in this project's directory.
out_dir="$repo_root/patches/$project"
mkdir -p "$out_dir"
last=$(find "$out_dir" -maxdepth 1 -name '[0-9][0-9][0-9][0-9]-*.patch' 2>/dev/null \
       | sed 's/.*\/\([0-9]\{4\}\)-.*/\1/' | sort -n | tail -1)
next=$(printf '%04d' $(( ${last:-0} + 1 )))

slug=$(printf '%s' "$subject" \
       | tr '[:upper:]' '[:lower:]' \
       | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-60)
file="$out_dir/$next-$slug.patch"

{
    echo "From: $(git -C "$dir" config user.name) <$(git -C "$dir" config user.email)>"
    echo "Subject: [$project] $subject"
    echo
    git -C "$dir" diff HEAD
} > "$file"

if [ ! -s "$file" ] || ! grep -q '^--- \|^diff --git' "$file"; then
    rm -f "$file"
    echo "no diff produced; is the change only in untracked files?" >&2
    exit 1
fi

echo "wrote patches/$project/$next-$slug.patch"
if [ "${#untracked[@]}" -gt 0 ]; then
    echo "included ${#untracked[@]} new file(s):"
    printf '    %s\n' "${untracked[@]}"
fi
echo "the change is still in your working tree; commit or keep it as you like"
