#!/bin/bash
# Upgrades the app on a simulator from each earlier version to this checkout, the way an
# App Store or TestFlight update does.
#
# For each "<label> <commit>" line on stdin (from versions.sh) it:
#   1. builds that commit and installs it fresh, then launches it, so it creates and seeds its store,
#   2. trains with it through UpgradeFixtureWriter.swift, which saves into that store,
#   3. installs this checkout over it, keeping the data, and launches it,
#   4. runs InstalledUpgradeTests, which checks every bit of the old data and keeps training.
# Each old store is also saved to <output-dir> as a fixture for UpgradeTests.
#
# Usage: scripts/upgrade/versions.sh HEAD | scripts/upgrade/upgrade-test.sh <simulator-udid> <output-dir>
set -uo pipefail

udid=$1
mkdir -p "$2"
out=$(cd "$2" && pwd)
root=$(git rev-parse --show-toplevel)
work=${UPGRADE_WORK:-${RUNNER_TEMP:-/tmp}/powerjack-upgrade}
bundle_id=com.stanleycloud.PowerJackv1
mkdir -p "$work" "$out/logs"

# Builds a checkout's app and tests for the simulator into its own DerivedData. Old versions
# share one, so each builds incrementally on the one before it.
build() { # <source-dir> <derived-data> <log-name>
  if ! xcodebuild build-for-testing \
    -project "$1/PowerJack/PowerJack.xcodeproj" \
    -scheme PowerJack \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$2" \
    COMPILER_INDEX_STORE_ENABLE=NO >"$out/logs/$3.log" 2>&1; then
    grep -E 'error:|BUILD FAILED' "$out/logs/$3.log" | head -30
    return 1
  fi
}

xctestrun() { ls "$1"/Build/Products/*.xctestrun | head -1; }
app() { echo "$1/Build/Products/Debug-iphonesimulator/PowerJack.app"; }

run_tests() { # <derived-data> <suite> <log-name>
  xcodebuild test-without-building \
    -xctestrun "$(xctestrun "$1")" \
    -destination "platform=iOS Simulator,id=$udid" \
    -only-testing:"PowerJackTests/$2" >"$out/logs/$3.log" 2>&1
  local status=$?
  [ $status -eq 0 ] || grep -E 'error|failed|Expectation|recorded an issue' "$out/logs/$3.log" | head -30
  return $status
}

# Launches the installed app like a lifter opening it, and fails if it doesn't stay open.
launch() { # <what>
  local marker pid report
  marker=$(mktemp)
  pid=$(xcrun simctl launch "$udid" "$bundle_id" | awk '{print $NF}')
  sleep 15
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    echo "$1 quit within 15 seconds of opening."
    report=$(find ~/Library/Logs/DiagnosticReports -name 'PowerJack*' -newer "$marker" 2>/dev/null | head -1)
    [ -n "$report" ] && head -c 8000 "$report"
    return 1
  fi
  xcrun simctl terminate "$udid" "$bundle_id"
}

support() {
  echo "$(xcrun simctl get_app_container "$udid" "$bundle_id" data)/Library/Application Support"
}

# Keeps the old store, folded into one file, plus what it holds.
save_fixture() { # <name>
  local dir copy
  dir=$(support)
  copy=$(mktemp -d)
  cp "$dir"/default.store* "$copy/"
  rm -f "$out/upgrade-$1.store"
  sqlite3 "$copy/default.store" "VACUUM INTO '$out/upgrade-$1.store'"
  cp "$dir/upgrade-manifest.json" "$out/upgrade-$1.json"
}

xcrun simctl bootstatus "$udid" -b >/dev/null

echo "::group::Build this version"
candidate="$work/candidate"
if ! build "$root" "$candidate" candidate-build; then
  echo "::endgroup::"
  echo "::error::This version doesn't build."
  exit 1
fi
echo "::endgroup::"

old_src="$work/old-source"
old="$work/old"
passed=""
failed=""

# Read from fd 3, so xcodebuild and simctl can't swallow the list on stdin.
while read -r label commit <&3; do
  [ -n "$label" ] || continue
  name=${label//\//-}
  echo "::group::Upgrade from $label (${commit:0:7})"
  failure=""

  if [ -e "$old_src/.git" ]; then
    git -C "$old_src" checkout -q --force --detach "$commit" && git -C "$old_src" clean -qfdx
  else
    git -C "$root" worktree add -q --force --detach "$old_src" "$commit"
  fi
  cp "$root/scripts/upgrade/UpgradeFixtureWriter.swift" "$old_src/PowerJack/PowerJackTests/"

  xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null
  if ! build "$old_src" "$old" "$name-build"; then
    failure="$label doesn't build"
  elif ! xcrun simctl install "$udid" "$(app "$old")" || ! launch "$label"; then
    failure="$label doesn't open on a fresh install"
  elif ! run_tests "$old" UpgradeFixtureWriter "$name-write"; then
    failure="$label couldn't save the lifter's data"
  elif ! save_fixture "$name"; then
    failure="$label's store couldn't be copied"
  elif ! xcrun simctl install "$udid" "$(app "$candidate")" || ! launch "The upgrade from $label"; then
    failure="the upgrade from $label doesn't open"
  elif ! TEST_RUNNER_POWERJACK_UPGRADE_FROM="$label" run_tests "$candidate" InstalledUpgradeTests "$name-verify"; then
    failure="the upgrade from $label lost or broke the lifter's data"
  elif [ "$(cat "$(support)/upgrade-verified" 2>/dev/null)" != "$label" ]; then
    failure="the check of the upgrade from $label didn't run"
  fi
  echo "::endgroup::"

  if [ -n "$failure" ]; then
    echo "::error::Upgrade from $label failed: $failure. Logs are in the upgrade-results artifact."
    failed="$failed $label"
  else
    echo "Upgrade from $label passed."
    passed="$passed $label"
  fi
done 3<&0

summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
{
  echo "### Upgrades to this version"
  echo
  echo "Passed ($(echo $passed | wc -w | tr -d ' ')):${passed:- none}"
  echo
  echo "Failed ($(echo $failed | wc -w | tr -d ' ')):${failed:- none}"
} >>"$summary"

[ -z "$failed" ]
