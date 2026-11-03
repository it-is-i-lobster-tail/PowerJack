#!/bin/bash
# Upgrades the app on a simulator from each earlier version to this checkout, the way an
# App Store or TestFlight update does.
#
# For each "<label> <commit>" line on stdin (from versions.sh) it:
#   1. builds that commit and installs it fresh, then opens it, so it creates and seeds its store,
#   2. trains with it through UpgradeFixtureWriter.swift, which saves into that store,
#   3. installs this checkout over it, keeping the data, and opens it, which upgrades the store,
#   4. keeps the upgraded store.
# Then InstalledUpgradeTests checks every upgraded store against what its old version saved.
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
    -parallel-testing-enabled NO \
    -only-testing:"PowerJackTests/$2" >"$out/logs/$3.log" 2>&1
  local status=$?
  # xcodebuild can shut the simulator down when it's done.
  boot
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
    # The app's last words, then its crash report.
    xcrun simctl spawn "$udid" log show --last 1m --style compact \
      --predicate 'process == "PowerJack" AND (messageType == error OR messageType == fault OR eventMessage CONTAINS[c] "fatal")' \
      2>/dev/null | tail -40
    report=$(find ~/Library/Logs/DiagnosticReports -name 'PowerJack*' -newer "$marker" 2>/dev/null | head -1)
    if [ -n "$report" ]; then
      cp "$report" "$out/logs/"
      grep -E '"(exception|termination|asi|crashed)"|fatal|Fatal error' "$report" | head -20
    fi
    return 1
  fi
  xcrun simctl terminate "$udid" "$bundle_id"
}

boot() {
  xcrun simctl boot "$udid" 2>/dev/null
  xcrun simctl bootstatus "$udid" -b >/dev/null
}

support() {
  echo "$(xcrun simctl get_app_container "$udid" "$bundle_id" data)/Library/Application Support"
}

# Copies the app's store, folded into one file, and what the old version saved in it.
copy_store() { # <store-path> <manifest-path>
  local dir copy
  dir=$(support)
  copy=$(mktemp -d)
  cp "$dir"/default.store* "$copy/" || return 1
  rm -f "$1"
  sqlite3 "$copy/default.store" "VACUUM INTO '$1'" || return 1
  cp "$dir/upgrade-manifest.json" "$2"
}

boot

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
upgraded="$out/upgraded"
mkdir -p "$upgraded"
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
  # Only to build with today's Xcode. Patches never touch how data is saved.
  if [ -f "$root/scripts/upgrade/patches/$name.patch" ]; then
    git -C "$old_src" apply "$root/scripts/upgrade/patches/$name.patch"
  fi

  xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null
  if ! build "$old_src" "$old" "$name-build"; then
    failure="$label doesn't build"
  elif ! xcrun simctl install "$udid" "$(app "$old")" || ! launch "$label"; then
    failure="$label doesn't open on a fresh install"
  elif ! run_tests "$old" UpgradeFixtureWriter "$name-write"; then
    failure="$label couldn't save the lifter's data"
  elif ! copy_store "$out/upgrade-$name.store" "$out/upgrade-$name.json"; then
    failure="$label's store couldn't be copied"
  elif ! xcrun simctl install "$udid" "$(app "$candidate")" || ! launch "The upgrade from $label"; then
    failure="the upgrade from $label doesn't open"
  elif ! mkdir -p "$upgraded/$name" || ! copy_store "$upgraded/$name/default.store" "$upgraded/$name/upgrade-manifest.json"; then
    failure="the upgraded store from $label couldn't be copied"
  fi
  echo "::endgroup::"

  if [ -n "$failure" ]; then
    rm -rf "${upgraded:?}/$name"
    echo "::error::Upgrade from $label failed: $failure. Logs are in the upgrade-results artifact."
    failed="$failed $label"
  fi
done 3<&0

# One test run checks every upgraded store, on a clean simulator.
if [ -n "$(ls "$upgraded")" ]; then
  echo "::group::Check the upgraded data"
  xcrun simctl uninstall "$udid" "$bundle_id" 2>/dev/null
  TEST_RUNNER_POWERJACK_UPGRADED_STORES="$upgraded" run_tests "$candidate" InstalledUpgradeTests check-upgraded
  echo "::endgroup::"
  for dir in "$upgraded"/*/; do
    name=$(basename "$dir")
    if [ -f "$dir/verified" ]; then
      echo "Upgrade from $name passed."
      passed="$passed $name"
    else
      echo "::error::Upgrade from $name failed: the upgrade lost or broke the lifter's data. See check-upgraded.log in the upgrade-results artifact."
      failed="$failed $name"
    fi
  done
fi

summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
{
  echo "### Upgrades to this version"
  echo
  echo "Passed ($(echo $passed | wc -w | tr -d ' ')):${passed:- none}"
  echo
  echo "Failed ($(echo $failed | wc -w | tr -d ' ')):${failed:- none}"
} >>"$summary"

[ -z "$failed" ]
