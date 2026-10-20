//
//  StrengthSlot.swift
//  PowerJack
//
//  A slot is one exercise at one place in the week (Definitions). These value types carry what the
//  planner wrote on a slot and what was logged on it, so the rules stay pure functions.
//

import Foundation

/// Why a slot looks the way it does. Stored on the slot, so later weeks can find the last normal one.
enum StrengthSlotKind: String, Codable {
    /// A lift's first weeks: loads by feel, then capped rises (2.2, 2.4).
    case calibration
    case normal
    case deload
    case microDeload
    /// The first and second week back after a break (12.2).
    case returnWeek1
    case returnWeek2
    /// Back after severe pain: 2 sets, 20% lighter (15.4).
    case painLighter
    /// After moderate pain: a set fewer, 10% lighter (15.5).
    case painCut
    /// Exercises that aren't priority lifts or their variants keep a double progression (5.1).
    case accessory

    /// Sessions that never feed Δ, e1RM, flags or plateau windows (10.7, 15.8).
    var isLight: Bool {
        self == .deload || self == .microDeload || self == .painLighter || self == .painCut
    }

    var isReturn: Bool { self == .returnWeek1 || self == .returnWeek2 }
}

struct StrengthPlannedSet: Equatable {
    var reps: Int?
    var loadKg: Double?
}

/// What the planner writes on one slot.
struct StrengthSlotPlan: Equatable {
    var kind: StrengthSlotKind
    /// R, the target reps before any reps-mode offset.
    var reps: Int
    /// I, the reps to leave on the last working set.
    var rir: Int
    var sets: [StrengthPlannedSet]
    /// Reps mode's offset on R while one load step is too coarse (1.2).
    var repOffset = 0
    /// The unrounded load target, so sub-step nudges build up (7.5). `nil` while loads are picked by feel.
    var intendedKg: Double?
    /// The break band (1-4) on return weeks.
    var returnBand = 0
    /// The rule IDs behind the plan, so the app can say why (principle 7).
    var rules: [String] = []
    /// Warm-ups worked out from the first working load (5.7). `nil` repeats last week's, as other styles do.
    var warmups: [StrengthPlannedSet]?

    var targetReps: Int { reps + repOffset }
    var repsToFailure: Int { reps + rir }
    var loadKg: Double? { sets.first?.loadKg }

    /// Stored in `WorkoutExercise.progressionCode`: the kind, its break band, then the rule IDs,
    /// e.g. "normal|7.3,9.3" or "returnWeek1.2|12.1,12.2".
    var code: String {
        let kindText = returnBand > 0 ? "\(kind.rawValue).\(returnBand)" : kind.rawValue
        return rules.isEmpty ? kindText : "\(kindText)|\(rules.joined(separator: ","))"
    }

    static func parse(code: String?) -> (kind: StrengthSlotKind, returnBand: Int, rules: [String])? {
        guard let code else { return nil }
        let parts = code.split(separator: "|", maxSplits: 1)
        let kindParts = (parts.first ?? "").split(separator: ".")
        guard let first = kindParts.first, let kind = StrengthSlotKind(rawValue: String(first)) else { return nil }
        let band = kindParts.count > 1 ? Int(kindParts[1]) ?? 0 : 0
        let rules = parts.count > 1 ? parts[1].split(separator: ",").map(String.init) : []
        return (kind, band, rules)
    }

    /// `count` sets (at least one) of `reps` at `loadKg`.
    static func uniform(_ count: Int, reps: Int?, loadKg: Double?) -> [StrengthPlannedSet] {
        Array(repeating: StrengthPlannedSet(reps: reps, loadKg: loadKg), count: max(1, count))
    }
}

/// One finished run of a slot: the plan it ran and what was logged.
struct StrengthSession: Equatable {
    struct LoggedSet: Equatable {
        var loadKg: Double?
        var reps: Int?
        /// What the planner had prefilled, to tell a user's change from the plan.
        var plannedLoadKg: Double?
        var completed: Bool
    }

    var plan: StrengthSlotPlan
    var sets: [LoggedSet]
    /// Reps left on the last completed working set. `nil` when it wasn't rated.
    var rir: Int?
    var pain: Int?
    var date: Date?

    var completedSets: [LoggedSet] { sets.filter { $0.completed && ($0.reps ?? 0) > 0 } }
    var trained: Bool { !completedSets.isEmpty }
    /// The rated set is the last completed working set (3.1).
    var ratedSet: LoggedSet? { completedSets.last }
    /// Moderate pain or worse: the session feeds nothing (15.8).
    var isPainful: Bool { (pain ?? 0) >= StrengthRules.painHold.rawValue }

    /// Sets that fell short of the target reps.
    var missedSets: [LoggedSet] { completedSets.filter { ($0.reps ?? 0) < plan.targetReps } }
    /// The plan had a load to build on, or one was lifted.
    var hasLoad: Bool { plan.intendedKg != nil || ratedSet?.loadKg != nil }

    /// Δ, the rep error on the rated set (7.2): (reps + RIR) − (R + I). A short set counts as RIR 0,
    /// and Δ is the lowest over the rated set and any short sets at its load or heavier.
    /// Unrated sets take RIR = I.
    var delta: Int? {
        guard let rated = ratedSet, let reps = rated.reps else { return nil }
        let target = plan.targetReps + plan.rir
        let ratedRIR = reps < plan.targetReps ? 0 : (rir ?? plan.rir)
        var delta = reps + ratedRIR - target
        for miss in missedSets where (miss.loadKg ?? 0) >= (rated.loadKg ?? 0) - 0.01 {
            delta = min(delta, (miss.reps ?? 0) - target)
        }
        return delta
    }
}
