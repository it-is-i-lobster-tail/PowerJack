//
//  Workout+Rest.swift
//  PowerJack
//
//  Derives the current set and the rest timer from stored completion times, so they survive relaunches.
//

import Foundation

extension Workout {
    /// The set to do next: the rest of the exercise or superset in progress first, then the first one with sets
    /// waiting. A superset takes one set of each exercise in turn (see `roundOrder(of:)`).
    var currentSet: (workoutExercise: WorkoutExercise, workoutSet: WorkoutSet)? {
        guard status == .active else { return nil }
        let inProgress = latestCompletedSet.map { [group(of: $0.workoutExercise)] } ?? []

        for group in inProgress + exerciseGroups {
            // Once its working sets are done, an exercise's leftover warmups aren't waiting.
            let next = Self.roundOrder(of: group).first {
                !$0.workoutExercise.allSetsDone() && $0.workoutSet.status == .active
            }
            if let next {
                return next
            }
        }
        return nil
    }

    /// The rest after the most recently completed set, while its exercise or superset still has a set waiting.
    /// Finishing the last set starts no rest, so the next exercise begins without a timer.
    /// A superset rests once each round is done, for the longest rest of the exercises in that round.
    var currentRest: RestPeriod? {
        guard
            let latest = latestCompletedSet,
            let current = currentSet,
            let exercise = current.workoutExercise.exercise
        else {
            return nil
        }

        let group = group(of: latest.workoutExercise)
        let round = latest.workoutExercise.round(of: latest.workoutSet)
        guard
            group.contains(where: { $0 === current.workoutExercise }),
            current.workoutExercise.round(of: current.workoutSet) != round
        else {
            return nil
        }
        let restDuration = group
            .filter { $0.set(in: round)?.status == .complete }
            .map(\.restDuration)
            .max() ?? latest.workoutExercise.restDuration

        let nextSet = current.workoutSet
        let sets = current.workoutExercise.workoutSets
        let loggedWeight = sets.last { $0.status == .complete && $0.weightTenthsPounds != nil }?.weightTenthsPounds
        let weight = nextSet.weightTenthsPlannedPounds ?? nextSet.weightTenthsPounds ?? loggedWeight

        return RestPeriod(
            startedAt: latest.completedAt,
            endsAt: latest.completedAt.addingTimeInterval(restDuration.timeInterval),
            exerciseName: exercise.exerciseName,
            setNumber: current.workoutExercise.number(of: nextSet),
            setCount: current.workoutExercise.count(sameTypeAs: nextSet),
            isWarmup: nextSet.isWarmup,
            reps: nextSet.repsPlanned ?? nextSet.reps,
            weightTenthsPounds: exercise.repsOnly ? nil : weight,
            usesKilograms: WeightUnit.current == .kilograms
        )
    }

    private var latestCompletedSet: (workoutExercise: WorkoutExercise, workoutSet: WorkoutSet, completedAt: Date)? {
        var latest: (workoutExercise: WorkoutExercise, workoutSet: WorkoutSet, completedAt: Date)?
        for workoutExercise in workoutExercises {
            for workoutSet in workoutExercise.workoutSets where workoutSet.status == .complete {
                guard let completedAt = workoutSet.completedAt,
                      completedAt > latest?.completedAt ?? .distantPast
                else {
                    continue
                }
                latest = (workoutExercise, workoutSet, completedAt)
            }
        }
        return latest
    }
}
