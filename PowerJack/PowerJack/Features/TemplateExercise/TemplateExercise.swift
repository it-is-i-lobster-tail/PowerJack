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
    private var templateExercise: Exercise
    private var order: Int
    
    init(templateExercise: Exercise, order: Int) {
        self.templateExercise = templateExercise
        self.order = order
    }
}
