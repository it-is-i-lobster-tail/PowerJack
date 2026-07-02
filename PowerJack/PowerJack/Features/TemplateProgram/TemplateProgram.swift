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
    var templateMuscleFocus: [Muscle]
    
    init(templateName: String, workoutsPerWeek: Int, templateMuscleFocus: [Muscle]) {
        self.templateName = templateName
        self.workoutsPerWeek = workoutsPerWeek
        self.templateWorkoutsValue = []
        self.templateMuscleFocus = templateMuscleFocus
    }
}
