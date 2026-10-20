//
//  StrengthSimulationTests.swift
//  PowerJackTests
//
//  Simulated lifters train on Strengthen programs for one to two years each, through the real planner and
//  models, and every week and workout the planner writes is checked against the strength rulebook
//  (`StrengthSimChecker`). Each lifter replays exactly from its seed.
//
//  The normal test run covers every archetype for half a year and a few random lifters for a year, so CI stays
//  quick. The full sweep and replays run on demand, with settings passed as TEST_RUNNER_ environment variables:
//
//      scripts/simulate-strength.sh                             # 300 random lifters and every archetype, 2 years each
//      scripts/simulate-strength.sh --lifters 1000 --weeks 52
//      scripts/simulate-strength.sh --seed 42                   # replay random lifter 42 with its week-by-week trace
//      scripts/simulate-strength.sh --seed 7 --profile chaos    # replay an archetype
//
//  A failing test prints the replay command for its lifter.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct StrengthSimulationTests {
    @Test("Every kind of lifter trains half a year of Strengthen programs without breaking a rule", arguments: StrengthSimProfile.archetypes.map(\.name))
    func archetype(_ name: String) throws {
        let profile = try #require(StrengthSimProfile.archetype(named: name))
        try expectSound(StrengthSimulation.run(profile, seed: StrengthSimulation.seed(for: name), weeks: 26), profile)
    }

    @Test("Random lifters train a year of Strengthen programs without breaking a rule", arguments: StrengthSimulation.smokeSeeds)
    func randomLifter(_ seed: UInt64) throws {
        let profile = StrengthSimProfile.random(seed: seed)
        try expectSound(StrengthSimulation.run(profile, seed: seed, weeks: 52), profile)
    }

    @Test("Principle 7: the same lifter and seed give the same weeks, workout for workout")
    func sameSeedSameWeeks() throws {
        let first = try StrengthSimulation.run(.chaos, seed: 2_026, weeks: 20)
        let second = try StrengthSimulation.run(.chaos, seed: 2_026, weeks: 20)
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.workouts == second.workouts && first.weeksChecked == second.weeksChecked)
        let other = try StrengthSimulation.run(.chaos, seed: 2_027, weeks: 20)
        #expect(other.fingerprint != first.fingerprint)
    }

    // MARK: On demand

    @Test("Full sweep: random lifters for two years each", .enabled(if: StrengthSimulation.sweep != nil), arguments: StrengthSimulation.sweepSeeds)
    func sweep(_ seed: UInt64) throws {
        let profile = StrengthSimProfile.random(seed: seed)
        try expectSound(StrengthSimulation.run(profile, seed: seed, weeks: StrengthSimulation.sweepWeeks), profile)
    }

    @Test("Full sweep: every archetype for two years", .enabled(if: StrengthSimulation.sweep != nil), arguments: StrengthSimProfile.archetypes.map(\.name))
    func sweepArchetype(_ name: String) throws {
        let profile = try #require(StrengthSimProfile.archetype(named: name))
        for offset in 0..<UInt64(4) {
            let seed = StrengthSimulation.seed(for: name) &+ offset
            try expectSound(StrengthSimulation.run(profile, seed: seed, weeks: StrengthSimulation.sweepWeeks), profile)
        }
    }

    @Test("Replay one lifter and print its weeks", .enabled(if: StrengthSimulation.replaySeed != nil))
    func replay() throws {
        let seed = try #require(StrengthSimulation.replaySeed)
        let name = StrengthSimulation.replayProfile ?? "random"
        let profile = name == "random" ? StrengthSimProfile.random(seed: seed) : try #require(StrengthSimProfile.archetype(named: name), "No archetype named \(name)")
        let report = try StrengthSimulation.run(profile, seed: seed, weeks: StrengthSimulation.sweepWeeks, keepsTrace: true)
        print(report.lines.joined(separator: "\n"))
        print("Rules: \(report.ruleSummary)")
        expectSound(report, profile)
    }

    /// No rule broken, and for lifters who rate honestly and show up, targets and estimates that track what they
    /// can lift: few beyond reach even fresh, few with more than 6 reps to spare, e1RMs within 20% of the truth.
    private func expectSound(_ report: StrengthSimReport, _ profile: StrengthSimProfile) {
        print("Strength simulation: \(report.headline)")
        #expect(report.weeksChecked > 0, "\(report.headline)")
        #expect(report.violations.isEmpty, "\(report.failureMessage)")
        if profile.isWellBehaved {
            #expect(report.tooHard <= 0.05 && report.tooEasy <= 0.1, "Targets drifted from what the lifter can lift. \(report.failureMessage)")
            #expect(report.e1rmOff <= 0.2, "Estimates drifted from the lifter's true maxes. \(report.failureMessage)")
        }
    }
}

/// Runs and settings for the simulation, read from the test runner's environment.
@MainActor
enum StrengthSimulation {
    private static let environment = ProcessInfo.processInfo.environment

    /// Random lifters in the normal test run.
    nonisolated static let smokeSeeds: [UInt64] = [13, 29, 47, 61]

    /// STRENGTH_SIM_SWEEP: how many random lifters the full sweep runs.
    static let sweep = environment["STRENGTH_SIM_SWEEP"].flatMap(Int.init)
    /// STRENGTH_SIM_FIRST_SEED: the sweep's first seed, so a sweep can continue where another stopped.
    static let firstSeed = environment["STRENGTH_SIM_FIRST_SEED"].flatMap(UInt64.init) ?? 1_000
    /// STRENGTH_SIM_WEEKS: calendar weeks per lifter in the sweep and replays.
    static let sweepWeeks = environment["STRENGTH_SIM_WEEKS"].flatMap(Int.init) ?? 104
    static let sweepSeeds = (0..<UInt64(sweep ?? 0)).map { firstSeed + $0 }

    /// STRENGTH_SIM_SEED and STRENGTH_SIM_PROFILE: the lifter to replay; the profile is "random" or an archetype's name.
    static let replaySeed = environment["STRENGTH_SIM_SEED"].flatMap(UInt64.init)
    static let replayProfile = environment["STRENGTH_SIM_PROFILE"]

    static func run(_ profile: StrengthSimProfile, seed: UInt64, weeks: Int, keepsTrace: Bool = false) throws -> StrengthSimReport {
        try quietly {
            try StrengthSimDriver(seed: seed, profile: profile, weeks: weeks, keepsTrace: keepsTrace).run()
        }
    }

    /// Runs `body` with the app's own log lines silenced: a year of workouts logs a warning for every skipped
    /// set, which would bury the test results. STRENGTH_SIM_APP_LOGS=1 keeps them.
    static func quietly<Result>(_ body: () throws -> Result) rethrows -> Result {
        guard environment["STRENGTH_SIM_APP_LOGS"] == nil else { return try body() }
        fflush(stderr)
        let saved = dup(STDERR_FILENO)
        let silent = open("/dev/null", O_WRONLY)
        dup2(silent, STDERR_FILENO)
        defer {
            fflush(stderr)
            dup2(saved, STDERR_FILENO)
            close(saved)
            close(silent)
        }
        return try body()
    }

    /// An archetype's own seed, so each one lives a different life.
    static func seed(for archetype: String) -> UInt64 {
        StrengthSimRandom.seed(archetype) % 100_000
    }
}
