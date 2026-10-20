//
//  BuildSimulationTests.swift
//  PowerJackTests
//
//  Simulated lifters train on Build programs for one to two years each, through the real planner and
//  models, and every week the planner writes is checked against the hypertrophy rulebook
//  (`BuildSimChecker`). Each lifter replays exactly from its seed.
//
//  The normal test run covers every archetype for a year and a few random lifters. The full sweep and
//  replays run on demand, with settings passed as TEST_RUNNER_ environment variables:
//
//      scripts/simulate-build.sh                          # 300 random lifters and every archetype, 2 years each
//      scripts/simulate-build.sh --lifters 1000 --weeks 52
//      scripts/simulate-build.sh --seed 42                # replay random lifter 42 with its week-by-week trace
//      scripts/simulate-build.sh --seed 7 --profile chaos  # replay an archetype
//
//  A failing test prints the replay command for its lifter.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct BuildSimulationTests {
    @Test("Every kind of lifter trains a year of Build programs without breaking a rule", arguments: BuildSimProfile.archetypes.map(\.name))
    func archetype(_ name: String) throws {
        let profile = try #require(BuildSimProfile.archetype(named: name))
        try expectSound(BuildSimulation.run(profile, seed: BuildSimulation.seed(for: name), weeks: 52), profile)
    }

    @Test("Random lifters train a year of Build programs without breaking a rule", arguments: BuildSimulation.smokeSeeds)
    func randomLifter(_ seed: UInt64) throws {
        let profile = BuildSimProfile.random(seed: seed)
        try expectSound(BuildSimulation.run(profile, seed: seed, weeks: 52), profile)
    }

    @Test("ENG-04: the same lifter and seed give the same weeks, workout for workout")
    func sameSeedSameWeeks() throws {
        let first = try BuildSimulation.run(.chaos, seed: 2_026, weeks: 30)
        let second = try BuildSimulation.run(.chaos, seed: 2_026, weeks: 30)
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.workouts == second.workouts && first.weeksChecked == second.weeksChecked)
        let other = try BuildSimulation.run(.chaos, seed: 2_027, weeks: 30)
        #expect(other.fingerprint != first.fingerprint)
    }

    // MARK: On demand

    @Test("Full sweep: random lifters for two years each", .enabled(if: BuildSimulation.sweep != nil), arguments: BuildSimulation.sweepSeeds)
    func sweep(_ seed: UInt64) throws {
        let profile = BuildSimProfile.random(seed: seed)
        try expectSound(BuildSimulation.run(profile, seed: seed, weeks: BuildSimulation.sweepWeeks), profile)
    }

    @Test("Full sweep: every archetype for two years", .enabled(if: BuildSimulation.sweep != nil), arguments: BuildSimProfile.archetypes.map(\.name))
    func sweepArchetype(_ name: String) throws {
        let profile = try #require(BuildSimProfile.archetype(named: name))
        for offset in 0..<UInt64(4) {
            let seed = BuildSimulation.seed(for: name) &+ offset
            try expectSound(BuildSimulation.run(profile, seed: seed, weeks: BuildSimulation.sweepWeeks), profile)
        }
    }

    @Test("Replay one lifter and print its weeks", .enabled(if: BuildSimulation.replaySeed != nil))
    func replay() throws {
        let seed = try #require(BuildSimulation.replaySeed)
        let name = BuildSimulation.replayProfile ?? "random"
        let profile = name == "random" ? BuildSimProfile.random(seed: seed) : try #require(BuildSimProfile.archetype(named: name), "No archetype named \(name)")
        let report = try BuildSimulation.run(profile, seed: seed, weeks: BuildSimulation.sweepWeeks, keepsTrace: true)
        print(report.lines.joined(separator: "\n"))
        print("Codes: \(report.codeSummary)")
        expectSound(report, profile)
    }

    /// No rule broken, and for lifters who rate honestly and show up, targets that track what they can lift:
    /// few beyond reach even fresh, and few with more than 8 reps to spare.
    private func expectSound(_ report: BuildSimReport, _ profile: BuildSimProfile) {
        print("Build simulation: \(report.headline)")
        #expect(report.weeksChecked > 0, "\(report.headline)")
        #expect(report.violations.isEmpty, "\(report.failureMessage)")
        if profile.isWellBehaved {
            #expect(report.tooHard <= 0.05 && report.tooEasy <= 0.25, "Targets drifted from what the lifter can lift. \(report.failureMessage)")
        }
    }
}

/// Runs and settings for the simulation, read from the test runner's environment.
@MainActor
enum BuildSimulation {
    private static let environment = ProcessInfo.processInfo.environment

    /// Random lifters in the normal test run.
    static let smokeSeeds: [UInt64] = [11, 23, 37, 41, 59, 73]

    /// BUILD_SIM_SWEEP: how many random lifters the full sweep runs.
    static let sweep = environment["BUILD_SIM_SWEEP"].flatMap(Int.init)
    /// BUILD_SIM_FIRST_SEED: the sweep's first seed, so a sweep can continue where another stopped.
    static let firstSeed = environment["BUILD_SIM_FIRST_SEED"].flatMap(UInt64.init) ?? 1_000
    /// BUILD_SIM_WEEKS: calendar weeks per lifter in the sweep and replays.
    static let sweepWeeks = environment["BUILD_SIM_WEEKS"].flatMap(Int.init) ?? 104
    static let sweepSeeds = (0..<UInt64(sweep ?? 0)).map { firstSeed + $0 }

    /// BUILD_SIM_SEED and BUILD_SIM_PROFILE: the lifter to replay; the profile is "random" or an archetype's name.
    static let replaySeed = environment["BUILD_SIM_SEED"].flatMap(UInt64.init)
    static let replayProfile = environment["BUILD_SIM_PROFILE"]

    static func run(_ profile: BuildSimProfile, seed: UInt64, weeks: Int, keepsTrace: Bool = false) throws -> BuildSimReport {
        try BuildSimDriver(seed: seed, profile: profile, weeks: weeks, keepsTrace: keepsTrace).run()
    }

    /// An archetype's own seed, so each one lives a different life.
    static func seed(for archetype: String) -> UInt64 {
        BuildSimRandom.seed(archetype) % 100_000
    }
}
