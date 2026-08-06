//
//  TemplateExerciseDraft.swift
//  PowerJack
//
//  Created by trogdor on 7/19/26.
//

import Foundation

struct TemplateExerciseDraft: Identifiable, Hashable {
    let id: UUID
    var order: Int
    var exercise: Exercise

    init(
        id: UUID = UUID(),
        order: Int,
        exercise: Exercise
    ) {
        self.id = id
        self.exercise = exercise
        self.order = order
    }
}
