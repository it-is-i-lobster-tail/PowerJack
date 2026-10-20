//
//  PowerJackSimulationTests.swift
//  PowerJackTests
//
//  Simulated lifters train on PowerJack programs for one to two years each, through the real planner and
//  models, and every week the planner writes is checked against the PowerJacking rulebook
//  (`PowerJackSimChecker`). Each lifter replays exactly from its seed.
//
//  The normal test run covers every archetype for half a year, a steady lifter for a year and a few
//  random lifters, so CI stays quick. The full sweep and replays run on demand, with settings passed as
//  TEST_RUNNER_ environment variables:
//
//      scripts/simulate-powerjack.sh                            # 300 random lifters and every archetype, 2 years each
//      scripts/simulate-powerjack.sh --lifters 1000 --weeks 52
//      scripts/simulate-powerjack.sh --seed 42                  # replay random lifter 42 with its week-by-week trace
//      scripts/simulate-powerjack.sh --seed 7 --profile chaos   # replay an archetype
//
//  A failing test prints the replay command for its lifter.
//

import Foundation
import Testing
@testable import PowerJack

@MainActor
struct PowerJackSimulationTests {
    @Test("Every kind of lifter trains half a year of PowerJack programs without breaking a rule", arguments: PowerJackSimProfile.archetypes.map(\.name))
    func archetype(_ name: String) throws {
        let profile = try #require(PowerJackSimProfile.archetype(named: name))
        try expectSound(PowerJackSimulation.run(profile, seed: PowerJackSimulation.seed(for: name), weeks: PowerJackSimulation.smokeWeeks), profile)
    }

    @Test("Random lifters train half a year of PowerJack programs without breaking a rule", arguments: PowerJackSimulation.smokeSeeds)
    func randomLifter(_ seed: UInt64) throws {
        let profile = PowerJackSimProfile.random(seed: seed)
        try expectSound(PowerJackSimulation.run(profile, seed: seed, weeks: PowerJackSimulation.smokeWeeks), profile)
    }

    @Test("The same lifter and seed give the same weeks, workout for workout")
    func sameSeedSameWeeks() throws {
        let first = try PowerJackSimulation.run(.chaos, seed: 2_026, weeks: 20)
        let second = try PowerJackSimulation.run(.chaos, seed: 2_026, weeks: 20)
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.workouts == second.workouts && first.weeksChecked == second.weeksChecked)
        let other = try PowerJackSimulation.run(.chaos, seed: 2_027, weeks: 20)
        #expect(other.fingerprint != first.fingerprint)
    }

    @Test("A steady lifter who gets stronger sees heavier main lifts after a year")
    func steadyLifterProgresses() throws {
        let report = try PowerJackSimulation.run(.steady, seed: PowerJackSimulation.seed(for: "steady"), weeks: 52)
        #expect(!report.mainLiftTrend.isEmpty, "\(report.headline)")
        for (lift, trend) in report.mainLiftTrend where trend.growth >= 1.08 {
            #expect(trend.last > trend.first, "\(lift): the lifter got \(Int((trend.growth - 1) * 100))% stronger, but its heavy load went \(trend.first) → \(trend.last)")
        }
    }

    // MARK: On demand

    @Test("Full sweep: random lifters for two years each", .enabled(if: PowerJackSimulation.sweep != nil), arguments: PowerJackSimulation.sweepSeeds)
    func sweep(_ seed: UInt64) throws {
        let profile = PowerJackSimProfile.random(seed: seed)
        try expectSound(PowerJackSimulation.run(profile, seed: seed, weeks: PowerJackSimulation.sweepWeeks), profile)
    }

    @Test("Full sweep: every archetype for two years", .enabled(if: PowerJackSimulation.sweep != nil), arguments: PowerJackSimProfile.archetypes.map(\.name))
    func sweepArchetype(_ name: String) throws {
        let profile = try #require(PowerJackSimProfile.archetype(named: name))
        for offset in 0..<UInt64(4) {
            let seed = PowerJackSimulation.seed(for: name) &+ offset
            try expectSound(PowerJackSimulation.run(profile, seed: seed, weeks: PowerJackSimulation.sweepWeeks), profile)
        }
    }

    @Test("Replay one lifter and print its weeks", .enabled(if: PowerJackSimulation.replaySeed != nil))
    func replay() throws {
        let seed = try #require(PowerJackSimulation.replaySeed)
        let name = PowerJackSimulation.replayProfile ?? "random"
        let profile = name == "random" ? PowerJackSimProfile.random(seed: seed) : try #require(PowerJackSimProfile.archetype(named: name), "No archetype named \(name)")
        let report = try PowerJackSimulation.run(profile, seed: seed, weeks: PowerJackSimulation.sweepWeeks, keepsTrace: true)
        print(report.lines.joined(separator: "\n"))
        print("Reasons: \(report.reasonSummary)")
        expectSound(report, profile)
    }

    /// No rule broken, and for lifters who rate honestly and show up, targets that track what they can lift:
    /// few beyond reach even fresh, and few with more than 8 reps to spare.
    private func expectSound(_ report: PowerJackSimReport, _ profile: PowerJackSimProfile) {
        print("PowerJack simulation: \(report.headline)")
        #expect(report.weeksChecked > 0, "\(report.headline)")
        #expect(report.violations.isEmpty, "\(report.failureMessage)")
        if profile.isWellBehaved {
            #expect(report.tooHard <= 0.05 && report.tooEasy <= 0.25, "Targets drifted from what the lifter can lift. \(report.failureMessage)")
        }
    }
}

/// Runs and settings for the simulation, read from the test runner's environment.
@MainActor
enum PowerJackSimulation {
    private static let environment = ProcessInfo.processInfo.environment

    /// Random lifters in the normal test run, and how long every smoke lifter trains.
    static let smokeSeeds: [UInt64] = [13, 61]
    static let smokeWeeks = 26

    /// POWERJACK_SIM_SWEEP: how many random lifters the full sweep runs.
    static let sweep = environment["POWERJACK_SIM_SWEEP"].flatMap(Int.init)
    /// POWERJACK_SIM_FIRST_SEED: the sweep's first seed, so a sweep can continue where another stopped.
    static let firstSeed = environment["POWERJACK_SIM_FIRST_SEED"].flatMap(UInt64.init) ?? 1_000
    /// POWERJACK_SIM_WEEKS: calendar weeks per lifter in the sweep and replays.
    static let sweepWeeks = environment["POWERJACK_SIM_WEEKS"].flatMap(Int.init) ?? 104
    static let sweepSeeds = (0..<UInt64(sweep ?? 0)).map { firstSeed + $0 }

    /// POWERJACK_SIM_SEED and POWERJACK_SIM_PROFILE: the lifter to replay; the profile is "random" or an archetype's name.
    static let replaySeed = environment["POWERJACK_SIM_SEED"].flatMap(UInt64.init)
    static let replayProfile = environment["POWERJACK_SIM_PROFILE"]

    static func run(_ profile: PowerJackSimProfile, seed: UInt64, weeks: Int, keepsTrace: Bool = false) throws -> PowerJackSimReport {
        try quietly {
            try PowerJackSimDriver(seed: seed, profile: profile, weeks: weeks, keepsTrace: keepsTrace).run()
        }
    }

    /// Runs `body` with the app's own log lines silenced: a year of workouts logs a line for every set,
    /// which would bury the test results. POWERJACK_SIM_APP_LOGS=1 keeps them.
    static func quietly<Result>(_ body: () throws -> Result) rethrows -> Result {
        guard environment["POWERJACK_SIM_APP_LOGS"] == nil else { return try body() }
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
        PowerJackSimRandom.seed(archetype) % 100_000
    }
}
