//
//  PowerJackLogs.swift
//  PowerJack
//
//  What the engine reads: each week as planned and logged, detached from SwiftData, and how
//  one exposure is read into effective RIR (R4.2), an outcome class (R4.5) and e1RM values (R8.2).
//

import Foundation

enum PowerJackWeekType: String {
    case build
    case deload
}

struct PowerJackSetLog: Equatable {
    var plannedReps: Int?
    var plannedLoad: Double?
    var reps: Int?
    var load: Double?
    var isComplete = false
    var isSkipped = false
    var completedAt: Date?

    /// A completed set as planned, for building test histories.
    static func done(_ reps: Int, at load: Double?, planned: Int? = nil, date: Date? = nil) -> PowerJackSetLog {
        PowerJackSetLog(
            plannedReps: planned ?? reps,
            plannedLoad: load,
            reps: reps,
            load: load,
            isComplete: true,
            completedAt: date
        )
    }
}

/// One slot of a week, as the engine planned it and the lifter logged it.
struct PowerJackEntryLog: Equatable {
    var exercise: PowerJackExercise
    /// Working sets, in order. Warm-ups never count.
    var sets: [PowerJackSetLog] = []
    /// TOP sets at the front of a TOP + BACK entry; 0 for straight sets.
    var topSets = 0
    var target: Int?
    /// The unrounded planned load of the straight sets, or of the BACK sets (R2.3).
    var loadTarget: Double?
    var topLoadTarget: Double?
    var calibrating = false
    /// The reps-left tap after the last working set (5 means 5+).
    var rir: Int?
    /// The reps-left tap after the last TOP set.
    var topRIR: Int?
    /// The effort word logged under another style.
    var legacyEffort: LevelOfEffort?
    var pain: LevelOfPain?
    var warmupsDisabled = false
}

struct PowerJackWorkoutLog: Equatable {
    var entries: [PowerJackEntryLog]
    var skipped = false
}

struct PowerJackWeekLog: Equatable {
    var type: PowerJackWeekType = .build
    var blockNumber = 1
    /// BUILD week i of its block (R5.1). 0 for a deload.
    var blockWeek = 1
    /// Target RIR column 1-4. 0 for a deload.
    var column = 1
    var workouts: [PowerJackWorkoutLog]

    /// Half or more of its workouts skipped: the block week doesn't advance (R6.1).
    var isPartial: Bool {
        guard !workouts.isEmpty else { return true }
        return Double(workouts.count(where: \.skipped)) / Double(workouts.count) >= PowerJackRules.partialShare
    }
}

/// One entry of an exercise logged anywhere, for anchors and start loads (R8.4, R9.1).
struct PowerJackExposure: Equatable {
    var date: Date
    var entry: PowerJackEntryLog
    /// Nil when logged under another style.
    var weekType: PowerJackWeekType?
    /// The tag it was planned with in a PowerJack week.
    var tag: PowerJackTag?
}

// MARK: - Reading an exposure

enum PowerJackSource: Equatable {
    case tapped, legacy, inferred
}

enum PowerJackClass: Equatable {
    case none, incomplete, missBig, missSmall, hard, met, easy

    var isMiss: Bool { self == .missBig || self == .missSmall }
    var rises: Bool { self == .met || self == .easy }
}

/// One part of an entry: its straight sets, or the TOP or the BACK sets of a TOP + BACK entry (R4.6).
struct PowerJackPart: Equatable {
    var sets: [PowerJackSetLog]
    var tap: Int?
    var legacyEffort: LevelOfEffort?
    var loadTarget: Double?
    var isTop = false

    var completed: [PowerJackSetLog] { sets.filter(\.isComplete) }
    var firstLoad: Double? { completed.first?.load ?? sets.first?.plannedLoad }
    var heaviestLoad: Double? { completed.compactMap(\.load).max() }
    var plannedReps: Int? { sets.last?.plannedReps }

    var source: PowerJackSource {
        if tap != nil { return .tapped }
        return legacyEffort != nil ? .legacy : .inferred
    }

    /// R4.2: a last set short of plan reads as 0, else the tap (legacy words through `RIR.legacyMap`).
    var effectiveRIR: Int? {
        guard let last = completed.last, let reps = last.reps else { return nil }
        if let planned = last.plannedReps, reps < planned { return 0 }
        if let tap { return tap }
        return legacyEffort.map { Self.legacyRIR($0) }
    }

    static func legacyRIR(_ effort: LevelOfEffort) -> Int {
        switch effort {
        case .brutal: 0
        case .veryHard: 1
        case .challenge: 2
        case .easy: 4
        case .veryEasy, .none: 5
        }
    }

    /// R4.5. `noSignal` covers deload weeks and pain-affected exposures.
    func outcome(role: PowerJackRole, target: Int, previous: PowerJackClass?, noSignal: Bool) -> PowerJackClass {
        if noSignal { return .none }
        if sets.contains(where: \.isSkipped) || completed.isEmpty { return .incomplete }
        let short = completed.reduce(0) { total, set in
            total + max(0, (set.plannedReps ?? set.reps ?? 0) - (set.reps ?? 0))
        }
        if short >= PowerJackRules.missBigReps || (short >= 1 && previous?.isMiss == true) { return .missBig }
        if short >= 1 { return .missSmall }
        guard source != .inferred, let rir = effectiveRIR, let last = completed.last, let reps = last.reps else {
            return .met
        }
        let planned = last.plannedReps ?? reps
        let tolerance = planned > PowerJackRules.highRepThreshold ? PowerJackRules.highRepTolerance : PowerJackRules.tolerance
        let gap = (reps + min(rir, PowerJackRules.rirCensor)) - (planned + target)
        if gap < -tolerance || (rir == 0 && role != .accessory) { return .hard }
        if source == .legacy { return .met }
        return gap > tolerance ? .easy : .met
    }

    /// R8.2: the best of a floor from every set and the estimates from rated or short sets.
    var value: (value: Double, hasEstimate: Bool)? {
        var best: Double?
        var hasEstimate = false
        let rated = completed.last
        for set in completed {
            guard let load = set.load, let reps = set.reps, reps > 0 else { continue }
            var candidates = [PowerJackPercent.e1RM(load: load, reps: reps, rir: 0)]
            if let planned = set.plannedReps, reps < planned {
                hasEstimate = true
            } else if set == rated, source == .tapped, let tap {
                if tap <= 4 { hasEstimate = true }
                candidates.append(PowerJackPercent.e1RM(load: load, reps: reps, rir: tap))
            }
            best = (candidates.compactMap { $0 } + [best].compactMap { $0 }).max()
        }
        return best.map { ($0, hasEstimate) }
    }
}

extension PowerJackEntryLog {
    var isTopAndBack: Bool { topSets > 0 }

    /// The straight part, or the TOP part followed by the BACK part.
    var parts: [PowerJackPart] {
        guard isTopAndBack else {
            return [PowerJackPart(sets: sets, tap: rir, legacyEffort: legacyEffort, loadTarget: loadTarget)]
        }
        let top = Array(sets.prefix(topSets))
        let back = Array(sets.dropFirst(topSets))
        // When the last completed set is a TOP set, one answer fills both (R4.1).
        let backDone = back.contains(where: \.isComplete)
        return [
            PowerJackPart(sets: top, tap: backDone ? (topRIR ?? rir) : (rir ?? topRIR), loadTarget: topLoadTarget, isTop: true),
            PowerJackPart(sets: back, tap: rir, loadTarget: loadTarget),
        ]
    }

    var hasCompletedSets: Bool { sets.contains(where: \.isComplete) }
    var lastCompletedAt: Date? { sets.compactMap(\.completedAt).max() }
}
