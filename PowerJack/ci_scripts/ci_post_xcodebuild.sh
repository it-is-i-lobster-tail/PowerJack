#!/bin/sh
# Xcode Cloud runs this after each build action. For archives it writes the
# TestFlight "What to Test" notes, so testers see what changed in each build.
# Xcode Cloud reads them from ci_scripts/TestFlight/WhatToTest.en-US.txt.

# Notes are a nice-to-have: never fail the build over them.
set -u

# Only archives go to TestFlight.
[ -n "${CI_APP_STORE_SIGNED_APP_PATH:-}" ] || exit 0

scripts_dir=$(cd "$(dirname "$0")" && pwd)
cd "${CI_PRIMARY_REPOSITORY_PATH:-$scripts_dir/../..}"

# Xcode Cloud may clone with little history; the notes need the version tags.
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    git fetch --quiet --unshallow --tags || git fetch --quiet --depth=200 --tags || true
else
    git fetch --quiet --tags || true
fi

if git rev-parse --verify --quiet HEAD^2 >/dev/null; then
    # A release merge into staging: everything it brought in from main.
    range="HEAD^1..HEAD"
elif previous=$(git describe --tags --abbrev=0 --match 'v*' HEAD^ 2>/dev/null); then
    # A push to main: everything since the previous version.
    range="$previous..HEAD"
else
    range="HEAD~1..HEAD"
fi

notes_dir="$scripts_dir/TestFlight"
notes="$notes_dir/WhatToTest.en-US.txt"
mkdir -p "$notes_dir"

# One line per change, using the pull request titles without their numbers.
changes=$(git log --no-merges --format='- %s' "$range" \
    | grep -v '^- Bump version' \
    | sed -E 's/ \(#[0-9]+\)$//' || true)

{
    echo "Build ${CI_BUILD_NUMBER:-} from ${CI_BRANCH:-${CI_COMMIT:-}}"
    echo
    if [ -n "$changes" ]; then
        echo "What's new:"
        echo "$changes"
    else
        echo "No app changes since the last build."
    fi
} | head -c 3900 > "$notes"

echo "What to Test notes:"
cat "$notes"
