//
//  Workout+Rest.swift
//  PowerJack
//
//  Derives the current set and the rest timer from stored completion times, so they survive relaunches.
//

import Foundation

extension Workout {
    /// The set to do next: the rest of the exercise in progress first, then the first exercise with sets waiting.
    var currentSet: (workoutExercise: WorkoutExercise, workoutSet: WorkoutSet)? {
        guard status == .active else { return nil }
        let inProgress = latestCompletedSet.map { [$0.workoutExercise] } ?? []

        for workoutExercise in inProgress + workoutExercises {
            if let workoutSet = workoutExercise.workoutSets.first(where: { $0.status == .active }) {
                return (workoutExercise, workoutSet)
            }
        }
        return nil
    }

    /// The rest after the most recently completed set, while its exercise still has a set waiting.
    /// Finishing an exercise's last set starts no rest, so the next exercise begins without a timer.
    var currentRest: RestPeriod? {
        guard
            let latest = latestCompletedSet,
            let current = currentSet,
            current.workoutExercise === latest.workoutExercise,
            let exercise = current.workoutExercise.exercise
        else {
            return nil
        }

        let nextSet = current.workoutSet
        let sets = current.workoutExercise.workoutSets
        let loggedWeight = sets.last { $0.status == .complete && $0.weightTenthsPounds != nil }?.weightTenthsPounds
        let weight = nextSet.weightTenthsPlannedPounds ?? nextSet.weightTenthsPounds ?? loggedWeight

        return RestPeriod(
            startedAt: latest.completedAt,
            endsAt: latest.completedAt.addingTimeInterval(exercise.restDuration.timeInterval),
            exerciseName: exercise.exerciseName,
            setNumber: nextSet.order + 1,
            setCount: sets.count,
            reps: nextSet.repsPlanned ?? nextSet.reps,
            weightTenthsPounds: exercise.repsOnly ? nil : weight
        )
    }

    private var latestCompletedSet: (workoutExercise: WorkoutExercise, completedAt: Date)? {
        var latest: (workoutExercise: WorkoutExercise, completedAt: Date)?
        for workoutExercise in workoutExercises {
            for workoutSet in workoutExercise.workoutSets where workoutSet.status == .complete {
                guard let completedAt = workoutSet.completedAt,
                      completedAt > latest?.completedAt ?? .distantPast
                else {
                    continue
                }
                latest = (workoutExercise, completedAt)
            }
        }
        return latest
    }
}
