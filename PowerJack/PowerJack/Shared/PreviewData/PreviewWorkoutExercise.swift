//
//  PreviewWorkoutExercise.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

class PreviewWorkoutExercise {
    // Barbell Bench Press
    static let workoutExerciseBarbellBenchPressPreview = WorkoutExercise (
        exercise: PreviewExerecise.exerciseBarbellBenchPressPreview,
        order: 0,
        workoutSets: [
            PreviewWorkoutSets.workoutSetBarbellBenchPressPreview0,
            PreviewWorkoutSets.workoutSetBarbellBenchPressPreview2
        ]
    )
    // Barbell Back Squat
    static let workoutExerciseBarbellBackSquatPreview = WorkoutExercise(
        exercise: PreviewExerecise.exerciseBarbellBackSquatPreview,
        order: 1,
        workoutSets: [
            PreviewWorkoutSets.workoutSetBarbellBackSquatPreview0,
            PreviewWorkoutSets.workoutSetBarbellBackSquatPreview1
        ]
    )
    
    // Body Pull Up
    static let workoutExerciseBodyPullUpPreview = WorkoutExercise(
        exercise: PreviewExerecise.exerciseBodyPullUpPreview,
        order: 2,
        workoutSets: [
            PreviewWorkoutSets.workoutSetBodyPullUpPreview0,
            PreviewWorkoutSets.workoutSetBodyPullUpPreview1
        ]
    )
    // Cable Lat Pull
    static let workoutSetCableLatPullPreview = WorkoutExercise(
        exercise: PreviewExerecise.exerciseCableLatPull,
        order: 3,
        workoutSets: [
            PreviewWorkoutSets.workoutSetCableLatPullPreview0,
            PreviewWorkoutSets.workoutSetCableLatPullPreview1
        ]
    )
    // Cable Lat Shoulder Raise
    static let workoutSetCableLateralShoulderRaisePreview = WorkoutExercise(
        exercise: PreviewExerecise.exerciseCableLateralShoulderRaise,
        order: 4,
        workoutSets: [
            PreviewWorkoutSets.workoutSetCableLateralShoulderRaise0,
            PreviewWorkoutSets.workoutSetCableLateralShoulderRaisePreview1
        ]
    )
    // Leg Press
    static let workoutSetLegPressPreview = WorkoutExercise(
        exercise: PreviewExerecise.LegPress,
        order: 5,
        workoutSets: [
            PreviewWorkoutSets.workoutSetLegPressPreview0,
            PreviewWorkoutSets.workoutSetLegPressPreview1
        ]
    )
}
