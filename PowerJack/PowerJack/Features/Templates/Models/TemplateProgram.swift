//
//  TemplateProgram.swift
//  PowerJack
//
//  Created by Brendon on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class TemplateProgram {
    var catalogID: String? = nil
    var templateName: String
    var workoutsPerWeek: Int
    var templateWorkoutsValue: [TemplateWorkout]
    var templateMuscleFocusValue: [Muscle]

    init(
        templateName: String,
        workoutsPerWeek: Int,
        templateMuscleFocus: [Muscle]
    ) {
        self.templateName = templateName
        self.workoutsPerWeek = max(0, workoutsPerWeek)
        self.templateWorkoutsValue = []
        self.templateMuscleFocusValue = templateMuscleFocus
    }
}

//
// Public Accesors
//
extension TemplateProgram {
    // Template Workouts
    var templateWorkouts: [TemplateWorkout] { templateWorkoutsValue.sorted { $0.order < $1.order} }
    // Template Muscle Focus
    var templateMuscleFocus: [Muscle] {
        get {
            templateMuscleFocusValue.sorted {
                $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending
            }
        }
        set {
            if newValue.count <= 4 {
                templateMuscleFocusValue = newValue
            }
        }
    }
}

//
// Mutations
//
extension TemplateProgram {
    
    @discardableResult
    func addTemplateWorkout() -> TemplateWorkout {
        let new = TemplateWorkout(
            order: templateWorkoutsValue.count
        )
        templateWorkoutsValue.append(new)
        return new
    }
    
    func clearAllTemplateWorkoutsValue() -> Void {
        // Delete the old rows so rebuilding the workouts doesn't leave orphans behind.
        for workout in templateWorkoutsValue {
            for exercise in workout.templateExercisesValue {
                modelContext?.delete(exercise)
            }
            modelContext?.delete(workout)
        }
        templateWorkoutsValue.removeAll()
    }
}
