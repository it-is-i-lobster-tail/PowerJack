//
//  PreviewExerecises.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

class PreviewExerecise {
    static let exerciseBarbellBenchPressPreview = Exercise(
        exerciseName: "Bench Press",
        exerciseEquipment: Equipment.Barbell,
        primaryMuscleFocus: Muscle.chest
    )
    static let exerciseBarbellBackSquatPreview = Exercise(
        exerciseName: "Back Squat",
        exerciseEquipment: Equipment.Barbell,
        primaryMuscleFocus: Muscle.quads
    )
    static let exerciseBodyPullUpPreview = Exercise(
        exerciseName: "Pull Up",
        exerciseEquipment: Equipment.Body,
        primaryMuscleFocus: Muscle.back
    )
    static let exerciseCableLatPull = Exercise(
        exerciseName: "Lat Pull",
        exerciseEquipment: Equipment.Cable,
        primaryMuscleFocus: Muscle.back
    )
    static let exerciseCableLateralShoulderRaise = Exercise(
        exerciseName: "Lateral Shoulder Raise",
        exerciseEquipment: Equipment.Cable,
        primaryMuscleFocus: Muscle.shoulders
    )
    static let LegPress = Exercise(
        exerciseName: "Leg Press",
        exerciseEquipment: Equipment.LegPress,
        primaryMuscleFocus: Muscle.quads
    )
}
