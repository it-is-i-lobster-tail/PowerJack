//
//  PreviewWorkout.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

class PreviewWorkout {
    static let workoutDay0Preview = Workout(
        order: 0,
        workoutExercises: [
            PreviewWorkoutExercise.workoutExerciseBarbellBenchPressPreview,
            PreviewWorkoutExercise.workoutExerciseBarbellBackSquatPreview,
        ]
    )
    static let workoutDay1Preview = Workout(
        order: 1,
        workoutExercises: [
            PreviewWorkoutExercise.workoutExerciseBodyPullUpPreview,
            PreviewWorkoutExercise.workoutSetCableLatPullPreview,
        ]
    )
    static let workoutDay2Preview = Workout(
        order: 2,
        workoutExercises: [
            PreviewWorkoutExercise.workoutSetCableLateralShoulderRaisePreview,
            PreviewWorkoutExercise.workoutSetLegPressPreview
        ]
    )
}
