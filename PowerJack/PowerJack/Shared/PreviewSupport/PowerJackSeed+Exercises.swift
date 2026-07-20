//
//  PowerJackSeed+Exercises.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

extension PowerJackSeed {
    static func makeExercises() -> [Exercise] {
        [
            Exercise(
                exerciseName: "Barbell Bench Press",
                exerciseEquipment: .barbell,
                primaryMuscleFocus: .chest
            ),
            Exercise(
                exerciseName: "Barbell Back Squat",
                exerciseEquipment: .barbell,
                primaryMuscleFocus: .quads
            ),
            Exercise(
                exerciseName: "Pull Up",
                exerciseEquipment: .bodyweight,
                primaryMuscleFocus: .back
            ),
            Exercise(
                exerciseName: "Lat Pulldown",
                exerciseEquipment: .cable,
                primaryMuscleFocus: .back
            ),
            Exercise(
                exerciseName: "Cable Lateral Raise",
                exerciseEquipment: .cable,
                primaryMuscleFocus: .shoulders
            ),
            Exercise(
                exerciseName: "Leg Press",
                exerciseEquipment: .legPress,
                primaryMuscleFocus: .quads
            ),
        ]
    }
}
