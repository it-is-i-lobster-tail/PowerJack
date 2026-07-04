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
    var templateName: String
    var workoutsPerWeek: Int
    var templateWorkoutsValue: [TemplateWorkout]
    var templateMuscleFocusValue: [Muscle]
    
    init(templateName: String, workoutsPerWeek: Int, templateMuscleFocus: [Muscle]) {
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
        get { templateMuscleFocusValue }
        set {
            if newValue.count <= 4 {
                templateMuscleFocusValue = newValue
            }
        }
    }
}
