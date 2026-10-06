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
    var orderValue: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.templateWorkoutValue)
    var templateExercisesValue: [TemplateExercise]? = []
    var templateProgramValue: TemplateProgram?

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
    var templateExercises: [TemplateExercise] { (templateExercisesValue ?? []).sorted(byOrder: \.order) }
}

//
// Mutations
//
extension TemplateWorkout {
    // Add TemplateExercise
    @discardableResult
    func addTemplateExercise(exercise: Exercise) -> TemplateExercise {
        let newTemplateExercise = TemplateExercise(
            exercise: exercise,
            order: templateExercises.count
        )
        templateExercisesValue = (templateExercisesValue ?? []) + [newTemplateExercise]
        return newTemplateExercise
    }
    // Move TemplateExercises
    func moveTemplateExercises(from source: IndexSet, to destination: Int) {
        var ordered = templateExercises
        ordered.moveAndReorder(from: source, to: destination)
        templateExercisesValue = ordered
    }
}
