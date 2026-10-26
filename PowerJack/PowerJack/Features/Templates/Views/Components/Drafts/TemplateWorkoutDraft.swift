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
        
        if let templateExercises {
            for templateExercise in templateExercises {
                guard let exercise = templateExercise.exercise else { continue }
                addTemplateExerciseDraft(
                    exercise: exercise,
                    supersetID: templateExercise.supersetID
                )
            }
            // A partner whose row lost its exercise leaves a lone superset ID behind.
            clearLoneSupersets()
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

    /// The exercises in order, with each superset's exercises in one block.
    var blocks: [TemplateExerciseBlock] {
        var blocks: [TemplateExerciseBlock] = []
        for draft in templateExerciseDrafts {
            if let supersetID = draft.supersetID, blocks.last?.exercises.last?.supersetID == supersetID {
                blocks[blocks.count - 1].exercises.append(draft)
            } else {
                blocks.append(TemplateExerciseBlock(exercises: [draft]))
            }
        }
        return blocks
    }

    /// An exercise on its own can stack with an exercise on its own next to it.
    func canStack(_ block: TemplateExerciseBlock) -> Bool {
        stackPartner(for: block) != nil
    }

    /// The exercise below, or above for the last one, when it isn't in a superset already.
    private func stackPartner(for block: TemplateExerciseBlock) -> TemplateExerciseBlock? {
        let blocks = blocks
        guard
            !block.isSuperset,
            let index = blocks.firstIndex(where: { $0.id == block.id })
        else {
            return nil
        }
        return [index + 1, index - 1]
            .filter(blocks.indices.contains)
            .map { blocks[$0] }
            .first { !$0.isSuperset }
    }
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
    mutating func addTemplateExerciseDraft(exercise: Exercise, supersetID: UUID? = nil) -> TemplateExerciseDraft? {
        // guard !contains(exercise) else { return nil }

        let newTemplateExerciseDraft = TemplateExerciseDraft(
            order: templateExerciseDraftsValue.count,
            exercise: exercise,
            supersetID: supersetID
        )
        templateExerciseDraftsValue.append(newTemplateExerciseDraft)
        return newTemplateExerciseDraft
    }

    mutating func removeTemplateExercises(at offsets: IndexSet) {
        var ordered = templateExerciseDrafts
        ordered.remove(atOffsets: offsets)
        reorder(&ordered)
        templateExerciseDraftsValue = ordered
        clearLoneSupersets()
    }

    mutating func moveTemplateExercises(from source: IndexSet, to destination: Int) {
        var ordered = templateExerciseDrafts

        guard destination >= 0, destination <= ordered.count else { return }
        guard source.allSatisfy({ ordered.indices.contains($0) }) else { return }

        ordered.move(fromOffsets: source, toOffset: destination)
        reorder(&ordered)
        templateExerciseDraftsValue = ordered
        clearLoneSupersets()
    }

    /// Moves whole blocks, so a superset's exercises stay together.
    mutating func moveBlocks(from source: IndexSet, to destination: Int) {
        var blocks = blocks

        guard destination >= 0, destination <= blocks.count else { return }
        guard source.allSatisfy({ blocks.indices.contains($0) }) else { return }

        blocks.move(fromOffsets: source, toOffset: destination)
        var ordered = blocks.flatMap(\.exercises)
        reorder(&ordered)
        templateExerciseDraftsValue = ordered
    }

    /// Stacks an exercise on its own with the one next to it (see `stackPartner(for:)`).
    mutating func stack(_ block: TemplateExerciseBlock) {
        guard let partner = stackPartner(for: block) else { return }
        let supersetID = UUID()
        let ids = Set((block.exercises + partner.exercises).map(\.id))
        for index in templateExerciseDraftsValue.indices where ids.contains(templateExerciseDraftsValue[index].id) {
            templateExerciseDraftsValue[index].supersetID = supersetID
        }
    }

    /// Splits a superset back into exercises on their own.
    mutating func unstack(_ block: TemplateExerciseBlock) {
        let ids = Set(block.exercises.map(\.id))
        for index in templateExerciseDraftsValue.indices where ids.contains(templateExerciseDraftsValue[index].id) {
            templateExerciseDraftsValue[index].supersetID = nil
        }
    }

    private func reorder(_ drafts: inout [TemplateExerciseDraft]) {
        for index in drafts.indices {
            drafts[index].order = index
        }
    }

    /// Only exercises next to each other share a superset, so an ID left on its own is cleared.
    private mutating func clearLoneSupersets() {
        let loneIDs = Set(blocks.filter { !$0.isSuperset }.map(\.id))
        for index in templateExerciseDraftsValue.indices where loneIDs.contains(templateExerciseDraftsValue[index].id) {
            templateExerciseDraftsValue[index].supersetID = nil
        }
    }
}
