//
//  TemplateExercise.swift
//  PowerJack
//
//  Created by Brendon on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class TemplateExercise {
    @Relationship(deleteRule: .nullify, inverse: \Exercise.templateExercisesValue)
    var exerciseValue: Exercise?
    var orderValue: Int = 0
    var templateWorkoutValue: TemplateWorkout?

    init(exercise: Exercise, order: Int) {
        self.exerciseValue = exercise
        self.orderValue = order
    }
}

//
// Public Accessors
//
extension TemplateExercise {
    // Exercise. Optional because a synced row can arrive before its exercise.
    var exercise: Exercise? {
        get {
            exerciseValue
        }
        set {
            exerciseValue = newValue
        }
    }
    // Order
    var order: Int {
        get {
            orderValue
        }
        set {
            orderValue = newValue
        }
    }
}

extension TemplateExercise: OrderedModel {}
