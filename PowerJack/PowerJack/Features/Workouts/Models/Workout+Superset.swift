//
//  Workout+Superset.swift
//  PowerJack
//
//  Exercises stacked into a superset in the template are done a round at a time:
//  one set of each exercise in turn, warmups first, then the working sets.
//

import Foundation

extension Workout {
    /// The supersets in order. Each gets a letter by its place: A for the first, then B, and so on.
    var supersets: [[WorkoutExercise]] { exerciseGroups.filter { $0.count > 1 } }

    /// The superset with this ID, or nil once it has ended.
    func superset(_ supersetID: UUID) -> [WorkoutExercise]? {
        supersets.first { $0[0].supersetID == supersetID }
    }

    /// "A" for the workout's first superset, "B" for the second, and so on.
    func supersetLetter(for superset: [WorkoutExercise]) -> String {
        Self.supersetLetter(at: supersets.firstIndex { $0.first === superset.first } ?? 0)
    }

    static func supersetLetter(at index: Int) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        return letters[min(index, letters.count - 1)]
    }

    /// The exercises in order, with each superset's exercises together. Only exercises next to each
    /// other with the same superset ID form one, so a lone ID is just an exercise on its own.
    var exerciseGroups: [[WorkoutExercise]] {
        var groups: [[WorkoutExercise]] = []
        for workoutExercise in workoutExercises {
            if let supersetID = workoutExercise.supersetID, groups.last?.last?.supersetID == supersetID {
                groups[groups.count - 1].append(workoutExercise)
            } else {
                groups.append([workoutExercise])
            }
        }
        return groups
    }

    /// The superset `workoutExercise` is in, or just the exercise when it stands alone.
    func group(of workoutExercise: WorkoutExercise) -> [WorkoutExercise] {
        exerciseGroups.first { $0.contains { $0 === workoutExercise } } ?? [workoutExercise]
    }

    /// A group's sets in the order they're done. A superset goes round by round, one set of each
    /// exercise per round, warmups before working sets. An exercise on its own just goes in set order.
    static func roundOrder(of group: [WorkoutExercise]) -> [(workoutExercise: WorkoutExercise, workoutSet: WorkoutSet)] {
        var order: [(workoutExercise: WorkoutExercise, workoutSet: WorkoutSet)] = []
        for setType in [SetType.warmup, .working] {
            let sets = group.map { ($0, setType == .warmup ? $0.warmupSets : $0.workingSets) }
            let rounds = sets.map(\.1.count).max() ?? 0
            for round in 0..<rounds {
                for (workoutExercise, exerciseSets) in sets where exerciseSets.indices.contains(round) {
                    order.append((workoutExercise, exerciseSets[round]))
                }
            }
        }
        return order
    }
}

extension WorkoutExercise {
    /// Where this exercise's superset sits in the workout: 0 for A, 1 for B. Nil when it stands alone.
    var supersetIndex: Int? {
        guard supersetID != nil, let workout = workoutValue else { return nil }
        return workout.supersets.firstIndex { $0.contains { $0 === self } }
    }

    /// The other exercises in this exercise's superset, in order. Empty when it stands alone.
    var supersetPartners: [WorkoutExercise] {
        guard supersetID != nil, let workout = workoutValue else { return [] }
        return workout.group(of: self).filter { $0 !== self }
    }

    /// The superset round `workoutSet` belongs to: its type and its 0-based place among sets of that type.
    func round(of workoutSet: WorkoutSet) -> SupersetRound {
        SupersetRound(isWarmup: workoutSet.isWarmup, index: number(of: workoutSet) - 1)
    }

    /// This exercise's set in `round`, if it has one.
    func set(in round: SupersetRound) -> WorkoutSet? {
        let sets = round.isWarmup ? warmupSets : workingSets
        return sets.indices.contains(round.index) ? sets[round.index] : nil
    }
}

nonisolated struct SupersetRound: Equatable {
    var isWarmup: Bool
    var index: Int
}
