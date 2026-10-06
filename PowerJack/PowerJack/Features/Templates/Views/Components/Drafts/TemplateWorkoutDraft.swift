//
//  TemplateWorkoutDraft.swift
//  PowerJack
//
//  Created by trogdor on 7/19/26.
//

import Foundation
import SwiftUI

struct TemplateWorkoutDraft: Identifiable {
    let id: UUID
    var enabled: Bool
    let orderValue: Int
    var templateExerciseDraftsValue: [TemplateExerciseDraft]

    init(
        id: UUID = UUID(),
        enabled: Bool,
        order: Int,
        templateExercises: [TemplateExercise]?
    ) {
        self.id = id
        self.enabled = enabled
        self.orderValue = order
        self.templateExerciseDraftsValue = []
        
        if let exercises = templateExercises {
            for exercise in exercises.compactMap(\.exercise) {
                addTemplateExerciseDraft(
                    exercise: exercise
                )
            }
        }
    }
}

//
// Public Accessors
//
extension TemplateWorkoutDraft {
    var order: Int {
        get { orderValue }
    }

    var templateExerciseDrafts: [TemplateExerciseDraft] { templateExerciseDraftsValue.sorted { $0.order < $1.order} }
}

//
// Mutations
//
extension TemplateWorkoutDraft {
//    func contains(_ exercise: Exercise) -> Bool {
//        templateExerciseDraftsValue.contains { draft in
//            guard let existingExercise = draft.exercise else { return false }
//            return existingExercise === exercise
//        }
//    }

    @discardableResult
    mutating func addTemplateExerciseDraft(exercise: Exercise) -> TemplateExerciseDraft? {
        // guard !contains(exercise) else { return nil }

        let newTemplateExerciseDraft = TemplateExerciseDraft(
            order: templateExerciseDraftsValue.count,
            exercise: exercise
        )
        templateExerciseDraftsValue.append(newTemplateExerciseDraft)
        return newTemplateExerciseDraft
    }

    mutating func removeTemplateExercises(at offsets: IndexSet) {
        var ordered = templateExerciseDrafts
        ordered.remove(atOffsets: offsets)
        reorder(&ordered)
        templateExerciseDraftsValue = ordered
    }

    mutating func moveTemplateExercises(from source: IndexSet, to destination: Int) {
        var ordered = templateExerciseDrafts

        guard destination >= 0, destination <= ordered.count else { return }
        guard source.allSatisfy({ ordered.indices.contains($0) }) else { return }

        ordered.move(fromOffsets: source, toOffset: destination)
        reorder(&ordered)
        templateExerciseDraftsValue = ordered
    }

    private func reorder(_ drafts: inout [TemplateExerciseDraft]) {
        for index in drafts.indices {
            drafts[index].order = index
        }
    }
}
