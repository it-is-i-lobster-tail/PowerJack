//
//  TemplateWorkout.swift
//  PowerJack
//
//  Created by Brendon on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class TemplateWorkout {
    var orderValue: Int
    var templateExercisesValue: [TemplateExercise]

    init(order: Int) {
        self.orderValue = order
        self.templateExercisesValue = []
    }
}

//
// Public Accesors
//
extension TemplateWorkout {
    // Order
    var order: Int { orderValue }
    // Template Exercises
    var templateExercises: [TemplateExercise] { templateExercisesValue.sorted { $0.order < $1.order } }
}

//
// Mutations
//
extension TemplateWorkout {
    // Add TemplateExercise
    func addTemplateExercise(exercise: Exercise) -> TemplateExercise {
        let newTemplateExercise = TemplateExercise(
            exercise: exercise,
            order: templateExercisesValue.count
        )
        templateExercisesValue.append(newTemplateExercise)
        return newTemplateExercise
    }
    // Move TemplateExercises
    func moveTemplateExercises(from source: IndexSet, to destination: Int) {
        var ordered = templateExercises
        ordered.moveAndReorder(from: source, to: destination)
        templateExercisesValue = ordered
    }
}
