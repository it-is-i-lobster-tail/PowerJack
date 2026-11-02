//
//  BuildModels.swift
//  PowerJack
//
//  The Build engine's inputs and outputs, detached from SwiftData so the engine stays a pure function.
//

import Foundation

/// What the engine needs to know about an exercise.
struct BuildExercise: Equatable {
    var minReps: Int
    var maxReps: Int
    var primary: Muscle
    var secondary: [Muscle] = []
    var repsOnly: Bool = false
    var fatigueLevel: FatigueLevel = .moderate

    /// Volume credit one working set gives each muscle: 1 to the primary, 0.5 to each secondary (VOL-01).
    var credits: [Muscle: Double] {
        var credits: [Muscle: Double] = [primary: 1]
        for muscle in Set(secondary) where muscle != primary {
            credits[muscle, default: 0] += BuildRules.secondaryCredit
        }
        return credits
    }
}

/// One logged or planned working set.
struct BuildSet: Equatable {
    var plannedReps: Int?
    var plannedLoad: Int?
    var reps: Int?
    var load: Int?
    var completed: Bool
    var completedAt: Date?
}

/// The effort tap on an exercise's last set.
enum BuildEffort: Equatable {
    /// Reps left, 0 to 5 where 5 means five or more.
    case tapped(Int)
    /// An old effort word read as reps left (RIR-02). Counts as unrated everywhere.
    case legacy(Int)
    case missing

    /// RIR.legacyMap: Brutal 0, Very Hard 1, Challenge 2, Easy 4, Very Easy 5+, None missing.
    init(legacy word: LevelOfEffort) {
        switch word {
        case .none: self = .missing
        case .veryEasy: self = .legacy(5)
        case .easy: self = .legacy(4)
        case .challenge: self = .legacy(2)
        case .veryHard: self = .legacy(1)
        case .brutal: self = .legacy(0)
        }
    }
}

/// Where a program week sits in its block.
struct BuildWeek: Equatable {
    var kind: WeekKind
    var blockWeek: Int
    /// The break band handled in this week, or 0.
    var returnBand: Int = 0
    /// The planned build weeks of a build week's block, laid out to fit the program (`ProgramBlocks`).
    var buildWeeks = BuildRules.buildWeeks
}

/// One week's performance of one slot.
struct BuildExposure: Equatable {
    /// Index of its week in `BuildInput.weeks`.
    var weekIndex: Int
    var sets: [BuildSet]
    var effort: BuildEffort = .missing
    var pain: LevelOfPain?
    /// The reps-left aim it was planned with.
    var rirTarget: Int?
    /// Why it was planned the way it was.
    var code: BuildReason.Code?
    var checkIn: ManualCheckIn = .none
    var checkInSourcePain: LevelOfPain?
    /// Trained within 48 hours of a hard session for the same muscle that ended at 0 reps left or short (FREQ-05).
    var shortGap: Bool = false
}

extension BuildExposure {
    var done: [BuildSet] { sets.filter(\.completed) }
    var isDone: Bool { sets.contains(where: \.completed) }
    var plannedSets: Int { sets.count }
    /// Every set shares one rep target. Nil when the sets were left blank, as in a calibration week.
    var repTarget: Int? { sets.lazy.compactMap(\.plannedReps).first }
    var plannedLoad: Int? { sets.lazy.compactMap(\.plannedLoad).last }
    /// The fewest reps in any completed set.
    var repsDone: Int? { done.compactMap { $0.reps ?? $0.plannedReps }.min() }
    /// The last completed set's load, else the planned load.
    var load: Int? { done.last.flatMap { $0.load ?? $0.plannedLoad } ?? plannedLoad }
    /// A completed set fell short of its planned reps.
    var missed: Bool {
        done.contains { set in
            guard let planned = set.plannedReps else { return false }
            return (set.reps ?? planned) < planned
        }
    }
    var tappedRIR: Int? {
        if case .tapped(let rir) = effort { return rir }
        return nil
    }
    /// From the last set and a tapped rating only (RIR-05). Inferred and legacy ratings give none.
    var estimatedMax: EstimatedMax? {
        guard
            let rir = tappedRIR,
            let last = done.last,
            let load = last.load ?? last.plannedLoad,
            let reps = last.reps ?? last.plannedReps
        else {
            return nil
        }
        return EstimatedMax(loadTenths: load, reps: reps, repsInReserve: rir)
    }
    var startedAt: Date? { done.compactMap(\.completedAt).min() }
    var endedAt: Date? { done.compactMap(\.completedAt).max() }
}

/// One exercise at one place in the program, with its history in this program.
struct BuildSlot: Equatable {
    /// The workout's place in the week.
    var workout: Int
    var exercise: BuildExercise
    /// Earlier exposures, oldest first.
    var history: [BuildExposure]
}

struct BuildInput: Equatable {
    /// Every week so far, oldest first. The last one is the week that just finished.
    var weeks: [BuildWeek]
    /// In program order: by workout, then by place in the workout.
    var slots: [BuildSlot]
    var focus: Set<Muscle> = []
    /// The program's length in weeks. Blocks past it run 4 build weeks, so 0 gives every block 4.
    var programWeeks = 0
}

struct BuildPlan: Equatable {
    var week: BuildWeek
    /// One per input slot, in the same order.
    var slots: [BuildSlotPlan]
}

struct BuildSlotPlan: Equatable {
    var sets: Int
    var reps: Int?
    var load: Int?
    /// Reps to leave on the last set.
    var rirTarget: Int
    var reason: BuildReason
    /// The exercise waits on a check-in because pain was this bad.
    var checkInPain: LevelOfPain?
}
