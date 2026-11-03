#!/bin/bash
# Lists every earlier version of the app as "<label> <commit>", oldest first.
#
# A version is each commit on main's first-parent history that set a new MARKETING_VERSION,
# which is the commit tagged v<version>. Every extra ref given (such as origin/staging, the
# build TestFlight testers have) is added as "<version>-<ref>". Commits with the same files as
# one already listed, or as <head>, are left out.
#
# Usage: scripts/upgrade/versions.sh <head> [extra-ref...]
set -euo pipefail

head=${1:-HEAD}
shift || true
project=PowerJack/PowerJack.xcodeproj/project.pbxproj

version_at() {
  git show "$1:$project" | sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' | sort -u | head -1
}

seen=" $(git rev-parse "$head^{tree}") "
emit() {
  local tree
  tree=$(git rev-parse "$2^{tree}")
  case "$seen" in *" $tree "*) return ;; esac
  seen="$seen$tree "
  echo "$1 $(git rev-parse "$2^{commit}")"
}

for commit in $(git log --first-parent --reverse --format=%H -G'MARKETING_VERSION' "$head" -- "$project"); do
  emit "$(version_at "$commit")" "$commit"
done

for ref in "$@"; do
  git rev-parse -q --verify "$ref^{commit}" >/dev/null || continue
  emit "$(version_at "$ref")-${ref##*/}" "$ref"
done
