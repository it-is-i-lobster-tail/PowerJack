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
    var order: Int
    var templateExercises: [TemplateExercise]
    
    init(order: Int, templateExercises: [TemplateExercise]) {
        self.order = order
        self.templateExercises = templateExercises
    }
}
