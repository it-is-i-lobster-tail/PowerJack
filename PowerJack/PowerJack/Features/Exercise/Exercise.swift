//
//  Exercise.swift
//  PowerJack
//
//  Created by Brendon on 6/25/26.
//

import Foundation
import SwiftData

@Model
final class Exercise {
    var exerciseName: String
    var exerciseEquipment: Equipment
    var primaryMuscleFocus: Muscle
    
    init(exerciseName: String, exerciseEquipment: Equipment, primaryMuscleFocus: Muscle) {
        self.exerciseName = exerciseName
        self.exerciseEquipment = exerciseEquipment
        self.primaryMuscleFocus = primaryMuscleFocus
    }
}
