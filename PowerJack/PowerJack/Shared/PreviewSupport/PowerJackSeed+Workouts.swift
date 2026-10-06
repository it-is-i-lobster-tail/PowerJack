//
//  PowerJackSeed+Workouts.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

extension PowerJackSeed {
    struct SeedSet {
        let plannedReps: Int?
        let plannedWeightTenthsPounds: Int?
        let actualReps: Int?
        let actualWeightTenthsPounds: Int?
        let status: Status
    }

    static func makeWorkout(
        order: Int,
        exercises: [Exercise],
        sets: [[SeedSet]]
    ) -> Workout {
        let workout = Workout(order: order)

        for (exerciseIndex, exercise) in exercises.enumerated() {
            guard let workoutExercise = workout.addWorkoutExercise(exercise: exercise) else {
                continue
            }

            let exerciseSets = sets.indices.contains(exerciseIndex) ? sets[exerciseIndex] : []
            for seedSet in exerciseSets {
                guard let workoutSet = workoutExercise.addSet(
                    plannedReps: seedSet.plannedReps,
                    plannedWeightTenthsPounds: seedSet.plannedWeightTenthsPounds
                ) else {
                    continue
                }

                workoutSet.reps = seedSet.actualReps
                workoutSet.weightTenthsPounds = seedSet.actualWeightTenthsPounds
                apply(seedSet.status, to: workoutSet)
            }
        }

        return workout
    }

    static func apply(_ status: Status, to workoutSet: WorkoutSet) {
        switch status {
        case .complete:
            workoutSet.complete()
        case .skipped:
            workoutSet.skip()
        case .stopped:
            workoutSet.stop()
        case .active, .planned:
            break
        }
    }
}
