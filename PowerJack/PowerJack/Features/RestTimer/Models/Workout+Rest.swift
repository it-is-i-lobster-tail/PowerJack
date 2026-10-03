//
//  Workout+Rest.swift
//  PowerJack
//
//  Derives the rest timer from stored completion times, so it survives relaunches.
//

import Foundation

extension Workout {
    /// The rest after the most recently completed set, while another set is still waiting.
    var currentRest: RestPeriod? {
        guard status == .active else { return nil }
        let exercises = workoutExercises

        var latest: (exerciseIndex: Int, completedAt: Date)?
        for (index, workoutExercise) in exercises.enumerated() {
            for workoutSet in workoutExercise.workoutSets where workoutSet.status == .complete {
                guard let completedAt = workoutSet.completedAt,
                      completedAt > latest?.completedAt ?? .distantPast
                else {
                    continue
                }
                latest = (index, completedAt)
            }
        }
        guard let latest else { return nil }

        // Finish the exercise in progress first, then the first exercise with sets waiting.
        let searchOrder = [latest.exerciseIndex] + Array(exercises.indices)
        guard
            let nextIndex = searchOrder.first(where: { index in
                exercises[index].workoutSets.contains { $0.status == .active }
            }),
            let nextSet = exercises[nextIndex].workoutSets.first(where: { $0.status == .active })
        else {
            return nil
        }

        let finishedExercise = exercises[latest.exerciseIndex].exercise
        let nextWorkoutExercise = exercises[nextIndex]
        let nextExercise = nextWorkoutExercise.exercise
        // Switching exercises rests for the longer of the two: too much rest beats too little.
        let restDuration = nextIndex == latest.exerciseIndex
            ? finishedExercise.restDuration
            : max(finishedExercise.restDuration, nextExercise.restDuration)

        let sets = nextWorkoutExercise.workoutSets
        let loggedWeight = sets.last { $0.status == .complete && $0.weightTenthsPounds != nil }?.weightTenthsPounds
        let weight = nextSet.weightTenthsPlannedPounds ?? nextSet.weightTenthsPounds ?? loggedWeight

        return RestPeriod(
            startedAt: latest.completedAt,
            endsAt: latest.completedAt.addingTimeInterval(restDuration.timeInterval),
            exerciseName: nextExercise.exerciseName,
            setNumber: nextSet.order + 1,
            setCount: sets.count,
            reps: nextSet.repsPlanned ?? nextSet.reps,
            weightTenthsPounds: nextExercise.repsOnly ? nil : weight
        )
    }
}
