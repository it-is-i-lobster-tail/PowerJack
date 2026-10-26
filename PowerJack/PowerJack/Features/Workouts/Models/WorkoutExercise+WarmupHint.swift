//
//  WorkoutExercise+WarmupHint.swift
//  PowerJack
//
//  Build warmups have no set target, so new lifters get a hint on how to warm up instead.
//

import Foundation
import SwiftData

extension WorkoutExercise {
    static let warmupHint = "Warmup with a weight that feels good and gets some blood moving. Add or remove warmup sets as needed to be ready for hard working sets."

    /// How many of a workout's first exercises show the warmup hint, by days since the lifter's first logged set:
    /// two in their first week of training, one in their second, then none.
    static func warmupHintExercises(daysIntoTraining days: Int) -> Int {
        switch days {
        case ..<7: 2
        case ..<14: 1
        default: 0
        }
    }

    /// Build workouts only. The weeks count from the first set logged in any program, not this program's weeks.
    var showsWarmupHint: Bool {
        guard templateType == .hypertrophy,
              let exercises = workoutValue?.workoutExercises,
              let index = exercises.firstIndex(where: { $0 === self })
        else {
            return false
        }
        // A workout counts from when it was done, so reopening an old one doesn't bring the hint back.
        let workoutDate = exercises.flatMap(\.workoutSets).compactMap(\.completedAt).min() ?? .now
        let firstSet = modelContext.flatMap(WorkoutSet.firstCompletedAt(in:)) ?? workoutDate
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: firstSet),
            to: calendar.startOfDay(for: workoutDate)
        ).day ?? 0
        return index < Self.warmupHintExercises(daysIntoTraining: days)
    }
}
