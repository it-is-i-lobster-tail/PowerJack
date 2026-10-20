//
//  StrengthSimReport.swift
//  PowerJackTests
//
//  What one simulated lifter did and what the checks found, with a week-by-week trace for replays and a
//  fingerprint of it for determinism checks.
//

import Foundation
@testable import PowerJack

struct StrengthSimReport {
    let seed: UInt64
    let profile: String
    let weeks: Int
    /// The lifter's main habits, for reading a random lifter's run.
    var habits = ""
    /// Keeps the trace lines, not just their fingerprint. Replays turn it on.
    var keepsTrace = false

    var programs = 0
    var programsFinished = 0
    var programsAbandoned = 0
    var otherStylePrograms = 0
    var workouts = 0
    var workoutsSkipped = 0
    var breaks = 0
    var unitSwitches = 0
    var stepChanges = 0
    var edits = 0
    var swaps = 0
    var checkIns = 0
    var weeksChecked = 0
    var workoutsChecked = 0
    var violations: [StrengthSimViolation] = []
    /// The most strength weeks closed by the lifter, so long runs show they reached advanced (17.7).
    var trainedWeeks = 0
    var experience = StrengthExperience.intermediate

    /// Reps left on a fresh first set at each normal-week priority target, from the lifter's true strength.
    private(set) var slacks: [Double] = []
    /// Each priority lift's final e1RM over the lifter's true one-rep max.
    private(set) var e1rmRatios: [Double] = []
    private(set) var kinds: [StrengthSlotKind: Int] = [:]
    private(set) var weekKinds: [WeekKind: Int] = [:]
    private(set) var rules: [String: Int] = [:]
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

    mutating func record(e1rmRatio: Double) {
        e1rmRatios.append(e1rmRatio)
    }

    mutating func count(kind: StrengthSlotKind?, rules slotRules: [String]) {
        guard let kind else { return }
        kinds[kind, default: 0] += 1
        for rule in slotRules {
            rules[rule, default: 0] += 1
        }
    }

    mutating func countWeek(_ kind: WeekKind?) {
        guard let kind else { return }
        weekKinds[kind, default: 0] += 1
    }

    /// Share of targets the lifter couldn't make even fresh (over a rep short), and share with more than 6 reps to spare.
    var tooHard: Double { share(of: slacks) { $0 < -1 } }
    var tooEasy: Double { share(of: slacks) { $0 > 6 } }
    var medianSlack: Double { median(slacks) }
    /// The share of priority lifts whose final e1RM sits more than 20% from the true max.
    var e1rmOff: Double { share(of: e1rmRatios) { abs($0 - 1) > 0.2 } }

    private func share(of values: [Double], _ test: (Double) -> Bool) -> Double {
        values.isEmpty ? 0 : Double(values.count(where: test)) / Double(values.count)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }

    /// One line on what the lifter lived through.
    var headline: String {
        let weekText = [WeekKind.build, .deload].map { "\(weekKinds[$0] ?? 0) \($0.rawValue)" }.joined(separator: ", ")
        let lifts = [StrengthSlotKind.calibration, .microDeload, .returnWeek1, .painLighter, .painCut]
            .map { "\(kinds[$0] ?? 0) \($0.rawValue)" }.joined(separator: ", ")
        return "\(profile) seed \(seed) (\(habits)), \(weeks) weeks: \(programs) programs (\(programsFinished) finished, "
            + "\(programsAbandoned) abandoned, \(otherStylePrograms) other styles), \(workouts) workouts, \(workoutsSkipped) skipped, "
            + "\(breaks) breaks, \(unitSwitches) unit switches, \(stepChanges) step changes, \(edits) edits, \(swaps) swaps, "
            + "\(checkIns) check-ins; \(weeksChecked) weeks and \(workoutsChecked) workouts checked (\(weekText); \(lifts)); "
            + "\(trainedWeeks) strength weeks logged, ending \(experience.rawValue); targets: median "
            + "\(String(format: "%.1f", medianSlack)) reps to spare, \(percent(tooHard)) too hard, \(percent(tooEasy)) too easy; "
            + (e1rmRatios.isEmpty ? "no recent e1RMs" : "e1RM: median \(String(format: "%.2f", median(e1rmRatios)))× true, \(percent(e1rmOff)) off by 20%+")
    }

    private func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// How often each rule ID was planned, most common first.
    var ruleSummary: String {
        rules.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
    }

    /// The first violations, with how to replay them.
    var failureMessage: String {
        let shown = violations.prefix(12).map { "  \($0)" }.joined(separator: "\n")
        let more = violations.count > 12 ? "\n  … and \(violations.count - 12) more" : ""
        return "\(headline)\n\(violations.count) violations:\n\(shown)\(more)\n"
            + "Replay: scripts/simulate-strength.sh --seed \(seed) --profile \(profile) --weeks \(weeks)"
    }
}
