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
    // Shared by the exercises stacked into one superset. Nil when the exercise stands alone.
    var supersetIDValue: UUID?
    var templateWorkoutValue: TemplateWorkout?

    init(exercise: Exercise, order: Int, supersetID: UUID? = nil) {
        self.exerciseValue = exercise
        self.orderValue = order
        self.supersetIDValue = supersetID
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
    // Superset
    var supersetID: UUID? { supersetIDValue }
}

extension TemplateExercise: OrderedModel {}
