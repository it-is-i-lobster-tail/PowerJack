//
//  BuildSimReport.swift
//  PowerJackTests
//
//  What one simulated lifter did and what the checks found, with a week-by-week trace for replays and a
//  fingerprint of it for determinism checks.
//

import Foundation
@testable import PowerJack

struct BuildSimReport {
    let seed: UInt64
    let profile: String
    let weeks: Int
    /// Keeps the trace lines, not just their fingerprint. Replays turn it on.
    var keepsTrace = false

    var programs = 0
    var programsFinished = 0
    var programsAbandoned = 0
    var workouts = 0
    var workoutsSkipped = 0
    var breaks = 0
    var returns = 0
    var edits = 0
    var weeksChecked = 0
    var violations: [BuildSimViolation] = []
    /// The most trained build weeks in a row with no deload, return week or break, across programs.
    var longestBuildRun = 0
    /// New-program exercises with no check-in though they were last done with Moderate pain or worse.
    var painLeftBehind = 0

    /// Reps left on a fresh first set at each progressing target, from the lifter's true strength.
    private(set) var slacks: [Double] = []
    private(set) var codes: [BuildReason.Code: Int] = [:]
    private(set) var weekKinds: [WeekKind: Int] = [:]
    private(set) var lines: [String] = []
    /// FNV-1a over every trace line: the same seed must give the same fingerprint.
    private(set) var fingerprint: UInt64 = 0xCBF2_9CE4_8422_2325

    init(seed: UInt64, profile: String, weeks: Int) {
        self.seed = seed
        self.profile = profile
        self.weeks = weeks
    }

    mutating func trace(_ line: String) {
        fingerprint = line.utf8.reduce(fingerprint ^ 0x0A) { ($0 ^ UInt64($1)) &* 0x0100_0000_01B3 }
        if keepsTrace {
            lines.append(line)
        }
    }

    mutating func record(slack: Double) {
        slacks.append(slack)
    }

    /// Share of targets the lifter couldn't make even fresh (over a rep short), and share with more than 8 reps to spare.
    var tooHard: Double { share { $0 < -1 } }
    var tooEasy: Double { share { $0 > 8 } }
    var medianSlack: Double {
        guard !slacks.isEmpty else { return 0 }
        return slacks.sorted()[slacks.count / 2]
    }

    private func share(_ test: (Double) -> Bool) -> Double {
        slacks.isEmpty ? 0 : Double(slacks.count(where: test)) / Double(slacks.count)
    }

    mutating func count(_ code: BuildReason.Code?) {
        guard let code else { return }
        codes[code, default: 0] += 1
    }

    mutating func countWeek(_ kind: WeekKind?) {
        guard let kind else { return }
        weekKinds[kind, default: 0] += 1
    }

    /// One line on what the lifter lived through.
    var headline: String {
        let kinds = [WeekKind.build, .deload, .return].map { "\(weekKinds[$0] ?? 0) \($0.rawValue)" }.joined(separator: ", ")
        return "\(profile) seed \(seed), \(weeks) weeks: \(programs) programs (\(programsFinished) finished, \(programsAbandoned) abandoned), "
            + "\(workouts) workouts, \(workoutsSkipped) skipped, \(breaks) breaks, \(returns) breaks handled, \(edits) edits; "
            + "\(weeksChecked) weeks checked (\(kinds)); targets: median \(String(format: "%.1f", medianSlack)) reps to spare, "
            + "\(percent(tooHard)) too hard, \(percent(tooEasy)) too easy; longest build run \(longestBuildRun) weeks; "
            + "\(painLeftBehind) painful exercises started fresh in a new program"
    }

    private func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// How often each reason code was planned, most common first.
    var codeSummary: String {
        codes.sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }
            .map { "\($0.key.rawValue) \($0.value)" }
            .joined(separator: ", ")
    }

    /// The first violations, with how to replay them.
    var failureMessage: String {
        let shown = violations.prefix(12).map { "  \($0)" }.joined(separator: "\n")
        let more = violations.count > 12 ? "\n  … and \(violations.count - 12) more" : ""
        return "\(headline)\n\(violations.count) violations:\n\(shown)\(more)\n"
            + "Replay: scripts/simulate-build.sh --seed \(seed) --profile \(profile) --weeks \(weeks)"
    }
}
