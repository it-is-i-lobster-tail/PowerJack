//
//  TemplateExerciseDraft.swift
//  PowerJack
//
//  Created by trogdor on 7/19/26.
//

import Foundation

struct TemplateExerciseDraft: Identifiable {
    let id: UUID
    var exercise: Exercise?
    var order: Int?

    init(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        order: Int? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.order = order
    }

    var canSave: Bool {
        exercise != nil && order != nil
    }
}
