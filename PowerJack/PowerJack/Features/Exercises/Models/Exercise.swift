//
//  Exercise.swift
//  PowerJack
//
//  Created by Brendon on 6/25/26.
//

import Foundation
import SwiftData

let maxExerciseNameLengthInput: Int = 30
let maxSecondaryMuscles: Int = 4

@Model
final class Exercise {
    var catalogID: String? = nil
    var exerciseName: String
    var exerciseEquipment: Equipment
    var primaryMuscleFocus: Muscle
    var secondaryMusclesValue: [Muscle]
    var userCreatedValue: Bool

    init(exerciseName: String, exerciseEquipment: Equipment, primaryMuscleFocus: Muscle, secondaryMuscles: [Muscle] = [], userCreated: Bool = false) {
        self.exerciseName = exerciseName
        self.exerciseEquipment = exerciseEquipment
        self.primaryMuscleFocus = primaryMuscleFocus
        self.secondaryMusclesValue = secondaryMuscles
        self.userCreatedValue = userCreated
    }
}

//
// Public
//
extension Exercise {
    var secondaryMuscles: [Muscle] {
        get { secondaryMusclesValue.sorted { $0.rawValue < $1.rawValue } }
        set {
            secondaryMusclesValue = newValue
        }
    }
    var userCreated: Bool { userCreatedValue }
}
