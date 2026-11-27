#!/bin/bash
# Prints the snapshot folder name for one earlier version: its commit, plus a hash of
# UpgradeFixtureWriter.swift and that version's build patch. Changing how a version is
# trained or built gives it a new name, so its old snapshot is never used again.
#
# Usage: scripts/upgrade/snapshot-name.sh <label> <commit>
set -euo pipefail

dir=$(cd "$(dirname "$0")" && pwd)
name=${1//\//-}
hash=$(cat "$dir/UpgradeFixtureWriter.swift" "$dir/patches/$name.patch" 2>/dev/null | shasum | cut -c1-12)
echo "$2-$hash"
