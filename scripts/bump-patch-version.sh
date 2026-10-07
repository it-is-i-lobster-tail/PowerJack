#!/bin/sh
# Raises MARKETING_VERSION by one patch (0.1.0 -> 0.1.1) for every target.
# Archive reads it as CFBundleShortVersionString, so TestFlight and the
# App Store see the same version as main.
set -eu

project="PowerJack/PowerJack.xcodeproj/project.pbxproj"

versions=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$project" | sort -u)
if [ "$(echo "$versions" | wc -l)" -ne 1 ]; then
  echo "Targets disagree on MARKETING_VERSION: $versions" >&2
  exit 1
fi

current="$versions"
major=$(echo "$current" | cut -d. -f1)
minor=$(echo "$current" | cut -d. -f2)
patch=$(echo "$current" | cut -d. -f3)
next="$major.${minor:-0}.$(( ${patch:-0} + 1 ))"

sed -i.bak "s/MARKETING_VERSION = $current;/MARKETING_VERSION = $next;/" "$project"
rm "$project.bak"
echo "$next"
