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
    /// Shared with the exercise it's stacked with. Nil when it stands alone.
    var supersetID: UUID?

    init(
        id: UUID = UUID(),
        order: Int,
        exercise: Exercise,
        supersetID: UUID? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.supersetID = supersetID
    }
}

/// One exercise, or the exercises stacked into a superset, shown as one card in the template builder.
struct TemplateExerciseBlock: Identifiable {
    var exercises: [TemplateExerciseDraft]

    var id: UUID { exercises[0].id }
    var isSuperset: Bool { exercises.count > 1 }
}
