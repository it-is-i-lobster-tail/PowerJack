#!/bin/bash
# Runs the Build (hypertrophy) engine simulation on demand: simulated lifters train
# on Build programs for up to two years each, and every planned week is checked
# against the rulebook (PowerJackTests/BuildSimulation).
#
#   scripts/simulate-build.sh                            # 300 random lifters and every archetype, 104 weeks each
#   scripts/simulate-build.sh --lifters 1000 --weeks 52  # a wider, shorter sweep
#   scripts/simulate-build.sh --first-seed 5000          # a different set of random lifters
#   scripts/simulate-build.sh --seed 42                  # replay random lifter 42 and print its weeks
#   scripts/simulate-build.sh --seed 7 --profile chaos   # replay an archetype (names in BuildSimProfile.archetypes)
#
# A failing lifter prints the replay command to use. Set SIMULATOR to pick the
# simulator by name (default "iPhone 17 Pro"), or SIMULATOR_ID for a UDID.
set -euo pipefail

lifters=300
weeks=104
first_seed=1000
seed=""
profile="random"

while [ $# -gt 0 ]; do
  case "$1" in
    --lifters) lifters="$2"; shift 2 ;;
    --weeks) weeks="$2"; shift 2 ;;
    --first-seed) first_seed="$2"; shift 2 ;;
    --seed) seed="$2"; shift 2 ;;
    --profile) profile="$2"; shift 2 ;;
    *) echo "Unknown option $1" >&2; exit 64 ;;
  esac
done

if [ -n "${SIMULATOR_ID:-}" ]; then
  destination="platform=iOS Simulator,id=$SIMULATOR_ID"
else
  destination="platform=iOS Simulator,name=${SIMULATOR:-iPhone 17 Pro}"
fi

cd "$(dirname "$0")/.."

export TEST_RUNNER_BUILD_SIM_WEEKS="$weeks"
if [ -n "$seed" ]; then
  export TEST_RUNNER_BUILD_SIM_SEED="$seed"
  export TEST_RUNNER_BUILD_SIM_PROFILE="$profile"
  only="PowerJackTests/BuildSimulationTests/replay()"
else
  export TEST_RUNNER_BUILD_SIM_SWEEP="$lifters"
  export TEST_RUNNER_BUILD_SIM_FIRST_SEED="$first_seed"
  only="PowerJackTests/BuildSimulationTests"
fi

# The app logs every model change, so keep only the test runner's own lines.
xcodebuild test \
  -project PowerJack/PowerJack.xcodeproj \
  -scheme PowerJack \
  -destination "$destination" \
  -parallel-testing-enabled NO \
  -only-testing:"$only" \
  2>&1 | grep -v -E '^[0-9-]+ [0-9:.]+ PowerJack\[[0-9:]+\]'
