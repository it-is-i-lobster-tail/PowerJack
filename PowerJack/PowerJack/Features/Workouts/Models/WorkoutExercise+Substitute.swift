//
//  WorkoutExercise+Substitute.swift
//  PowerJack
//
//  One-Time Substitute: when the equipment is busy, the lifter swaps in another exercise for the same
//  muscle, for this workout only. `exercise` stays the planned exercise, so next week, Edit Days, Reset
//  Progression and templates never see the swap, and progression counts the work toward the planned exercise.
//

import Foundation
import OSLog

extension WorkoutExercise {
    var substitute: Exercise? { substituteValue }
    /// What the lifter is actually doing: the substitute when there is one, else the planned exercise.
    var shownExercise: Exercise? { substituteValue ?? exercise }

    /// Only before any working set is logged, since the logged sets would mix two exercises.
    var canSubstitute: Bool {
        !locked && status == .active && completedWorkingSets == 0
    }

    /// Exercises that can stand in for the planned one: the same primary muscle, sorted by name.
    func substituteOptions(from exercises: [Exercise]) -> [Exercise] {
        guard let exercise else { return [] }
        return exercises
            .filter { $0 !== exercise && $0.primaryMuscleFocus == exercise.primaryMuscleFocus }
            .sorted { $0.exerciseName.localizedStandardCompare($1.exerciseName) == .orderedAscending }
    }

    /// Swaps `substitute` in for this workout. Sets still to do take its weights from the last time it was done.
    /// Reps keep the plan.
    func substitute(with substitute: Exercise) {
        guard canSubstitute, substitute !== exercise else {
            Logger.workoutExercise.warning("Can only substitute an exercise before its working sets are logged.")
            return
        }
        let keepsPlanned = substituteValue == nil
        substituteValue = substitute
        for type in [SetType.warmup, .working] {
            let sets = workoutSets.filter { $0.setType == type }
            let weights = Self.lastWeights(of: substitute, type: type, excluding: self)
            for (index, workoutSet) in sets.enumerated() {
                let weight = weights.isEmpty ? nil : weights[min(index, weights.count - 1)]
                workoutSet.substituteWeight(weight, keepingPlanned: keepsPlanned)
            }
        }
        TraceLog.record(.workout, "Substituted \(substitute.traceName) for \(traceDescription)")
    }

    /// Back to the planned exercise, with its planned weights.
    func undoSubstitute() {
        guard canSubstitute, substituteValue != nil else {
            Logger.workoutExercise.warning("Can only undo a substitute before its working sets are logged.")
            return
        }
        substituteValue = nil
        for workoutSet in workoutSets {
            workoutSet.restorePlannedWeight()
        }
        TraceLog.record(.workout, "Undid the substitute for \(traceDescription)")
    }

    /// The weights of `exercise`'s most recently logged sets of `type`, done as itself or as a substitute.
    static func lastWeights(of exercise: Exercise, type: SetType, excluding row: WorkoutExercise) -> [Int?] {
        let ownRows = (exercise.workoutExercisesValue ?? []).filter { $0.substitute == nil }
        let rows = ownRows + (exercise.substitutedWorkoutExercisesValue ?? [])
        let logged = rows
            .filter { $0 !== row }
            .map { $0.workoutSets.filter { $0.setType == type && $0.status == .complete } }
            .filter { !$0.isEmpty }
        let latest = logged.max { lastLogged($0) < lastLogged($1) }
        return latest?.map(\.weightTenthsPounds) ?? []
    }

    private static func lastLogged(_ sets: [WorkoutSet]) -> Date {
        sets.compactMap(\.completedAt).max() ?? .distantPast
    }
}

extension WorkoutSet {
    /// Set of an exercise done as a one-time substitute.
    var isSubstituted: Bool { workoutExerciseValue?.substitute != nil }

    // What progression reads. A substitute's loads aren't comparable to the planned exercise's, so its sets
    // read as the planned exercise done to plan: its planned weight and planned reps. Skipped sets stay skipped.
    var progressionReps: Int? { isSubstituted ? repsPlanned ?? reps : reps }
    var progressionWeightTenthsPounds: Int? { isSubstituted ? originalPlannedWeightTenthsPounds : weightTenthsPounds }
    var progressionPlannedWeightTenthsPounds: Int? {
        isSubstituted ? originalPlannedWeightTenthsPounds : weightTenthsPlannedPounds
    }
}
