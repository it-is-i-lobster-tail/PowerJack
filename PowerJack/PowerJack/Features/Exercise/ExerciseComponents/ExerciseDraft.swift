//
//  ExerciseDraft.swift
//  PowerJack
//
//  Created by Brendon on 7/8/26.
//

struct ExerciseDraft {
    var name: String = ""
    var equipment: Equipment?
    var primaryMuscle: Muscle?
    var secondaryMuscles: [Muscle] = []

    
    init() {}
    
    init(exercise: Exercise) {
        name = exercise.exerciseName
        equipment = exercise.exerciseEquipment
        primaryMuscle = exercise.primaryMuscleFocus
        secondaryMuscles = exercise.secondaryMusclesValue
    }
    
    var canSave: Bool {
        equipment != nil && primaryMuscle != nil && name.count > 3
    }
    
    mutating func removePrimaryFromSecondary() {
        guard let primaryMuscle else { return }
        secondaryMuscles.removeAll { $0 == primaryMuscle }
    }
    
}
