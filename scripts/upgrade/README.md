# Upgrade tests

Every earlier version of PowerJack must upgrade to the latest one without losing or breaking anything. Two layers check this.

## Unit tests (every PR)

`PowerJackTests/Upgrade/UpgradeTests` opens each store in `PowerJackTests/UpgradeFixtures` with today's model, seeds it like the app's launch, and checks:

- the lifter's programs, finished workouts, logged sets, weights and reps, feedback, volume history, own exercises and own templates are all still there,
- the running workout can be finished and the program moves on,
- the first screen shows the upgraded program.

Each `upgrade-<version>.store` is the real store that version saved after training with it, and `upgrade-<version>.json` lists what it held.

## Full upgrade (PRs into staging)

`.github/workflows/upgrade-tests.yml` runs the "Upgrade tests" check. For every earlier version (`versions.sh`: each commit on main that set a new version, tagged `v<version>`, plus the tips of staging and prod) it:

1. builds that version and installs it fresh on a simulator, then opens it, so it creates and seeds its own store,
2. trains with it through `UpgradeFixtureWriter.swift`, which is copied into that version's tests: a finished program from a built-in template, plus the lifter's own exercise and template with week 1 done and week 2 mid-workout,
3. installs the new version over it, keeping the data like an App Store update, and opens it, which upgrades the store (it fails if the app quits),
4. copies the upgraded store off the simulator.

Then one run of `InstalledUpgradeTests` checks every upgraded store with the same checks as the unit tests.

Versions are split over four runners. PRs into main run it only when they change the upgrade tests.

`UpgradeFixtureWriter.swift` has to compile against every version back to 1.0, so it only uses APIs that 1.0 already had.

A version that no longer builds with CI's Xcode gets the smallest fix that makes it build in `patches/<version>.patch`. A patch must never change how data is saved. 1.0 was built with a newer Xcode than CI's, so `patches/1.0.patch` adds the TipKit defaults and the widget bundle ID that 0.1.0 has.

## Adding a fixture

When a version changes the saved model, add its store to the unit tests: run the Upgrade tests workflow, download the `upgrade-results-*` artifacts, and copy that version's `upgrade-<version>.store` and `.json` into `PowerJack/PowerJackTests/UpgradeFixtures`.

## Running it locally

```bash
udid=$(xcrun simctl create "Upgrade" "iPhone 17 Pro")
scripts/upgrade/versions.sh HEAD | tail -3 | scripts/upgrade/upgrade-test.sh "$udid" upgrade-results
```
