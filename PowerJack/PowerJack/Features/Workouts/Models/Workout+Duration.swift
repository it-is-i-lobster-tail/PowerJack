//
//  Workout+Duration.swift
//  PowerJack
//
//  How long a workout, each exercise, and each set took, from stored start and completion times.
//  A set's clock starts when the set before it was logged anywhere in the workout, so exercises
//  done back to back (A1, B1, A2, B2) each get the time since the set before.
//

import Foundation

extension Workout {
    /// Time since Start Workout, up to when it ended or `now` while it's running.
    func duration(at now: Date = .now) -> TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    /// Where the clock of a set logged at `date` starts: the latest set logged before it, or the workout's start.
    func setClockStart(before date: Date) -> Date? {
        let completions = workoutExercises
            .flatMap(\.workoutSets)
            .compactMap { $0.status == .complete ? $0.completedAt : nil }
            .filter { $0 <= date }
        return completions.max() ?? startedAt
    }
}

extension WorkoutExercise {
    /// The time of its logged sets added up. Back to back, that's first set to last; in a superset,
    /// each exercise keeps only its own sets, so the exercises still add up to the workout.
    /// `nil` until a set with a start time is logged.
    var duration: TimeInterval? {
        let durations = workoutSets.compactMap(\.duration)
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }
}
