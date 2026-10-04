//
//  PowerJackSeed+Exercises.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftData

struct PowerJackExercises {
    let container: ModelContainer
    let exercises: [Exercise]
}

extension PowerJackSeed {
    static func exercises() -> PowerJackExercises {
        let container = makeInMemoryContainer()
        let exercises = makeExercises()
        
        for exercise in exercises {
            container.mainContext.insert(exercise)
        }
        
        do {
            try container.mainContext.save()
        } catch {
            fatalError("Could not save seeded in-memory data: \(error)")
        }
        
        return PowerJackExercises(
            container: container,
            exercises: exercises,
        )
    }
}

extension PowerJackSeed {
    static func makeExercises() -> [Exercise] {
        [
            Exercise(
                exerciseName: "Barbell Bench Press",
                exerciseEquipment: .barbell,
                primaryMuscleFocus: .chest,
                secondaryMuscles: [.triceps, .shoulders],
                minReps: 5,
                maxReps: 12,
                fatigueLevel: .high
            ),
            Exercise(
                exerciseName: "Barbell Back Squat",
                exerciseEquipment: .barbell,
                primaryMuscleFocus: .quads,
                secondaryMuscles: [.glutes, .hamstrings],
                minReps: 6,
                maxReps: 12,
                fatigueLevel: .high
            ),
            Exercise(
                exerciseName: "Pull Up",
                exerciseEquipment: .bodyweight,
                primaryMuscleFocus: .back,
                secondaryMuscles: [.biceps, .forearms],
                minReps: 5,
                maxReps: 12,
                fatigueLevel: .moderate
            ),
            Exercise(
                exerciseName: "Lat Pulldown",
                exerciseEquipment: .cable,
                primaryMuscleFocus: .back,
                secondaryMuscles: [.biceps],
                minReps: 8,
                maxReps: 15,
                fatigueLevel: .moderate
            ),
            Exercise(
                exerciseName: "Cable Lateral Raise",
                exerciseEquipment: .cable,
                primaryMuscleFocus: .shoulders,
                secondaryMuscles: [],
                minReps: 10,
                maxReps: 25,
                fatigueLevel: .low
            ),
            Exercise(
                exerciseName: "Leg Press",
                exerciseEquipment: .legPress,
                primaryMuscleFocus: .quads,
                secondaryMuscles: [.glutes],
                minReps: 8,
                maxReps: 15,
                fatigueLevel: .high
            ),
        ]
    }
}
