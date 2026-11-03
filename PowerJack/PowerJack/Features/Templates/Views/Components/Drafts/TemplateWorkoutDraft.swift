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

    /// Each superset gets a letter by its place in the day: A for the first, then B, and so on to Z.
    static let supersetLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)

    var supersets: [TemplateExerciseBlock] { blocks.filter(\.isSuperset) }

    func supersetLetter(for block: TemplateExerciseBlock) -> String {
        let index = supersets.firstIndex { $0.id == block.id } ?? 0
        return Self.supersetLetters[min(index, Self.supersetLetters.count - 1)]
    }

    var canStartSuperset: Bool { supersets.count < Self.supersetLetters.count }
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

    /// Adds another workout's exercises in their order. Replacing clears this workout first.
    mutating func copyTemplateExercises(from source: TemplateWorkoutDraft, replacing: Bool) {
        if replacing {
            templateExerciseDraftsValue = []
        }

        for templateExerciseDraft in source.templateExerciseDrafts {
            addTemplateExerciseDraft(exercise: templateExerciseDraft.exercise)
        }
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

    /// Turns an exercise on its own into a new superset, ready for others to join.
    mutating func startSuperset(with block: TemplateExerciseBlock) {
        guard !block.isSuperset, canStartSuperset else { return }
        let supersetID = UUID()
        let ids = Set(block.exercises.map(\.id))
        for index in templateExerciseDraftsValue.indices where ids.contains(templateExerciseDraftsValue[index].id) {
            templateExerciseDraftsValue[index].supersetID = supersetID
        }
    }

    /// Moves an exercise on its own to the end of `superset` and joins it.
    mutating func add(_ block: TemplateExerciseBlock, to superset: TemplateExerciseBlock) {
        guard
            !block.isSuperset,
            let supersetID = superset.exercises[0].supersetID,
            let last = superset.exercises.last
        else {
            return
        }

        var ordered = templateExerciseDrafts
        var joining = block.exercises[0]
        ordered.removeAll { $0.id == joining.id }
        guard let lastIndex = ordered.firstIndex(where: { $0.id == last.id }) else { return }

        joining.supersetID = supersetID
        ordered.insert(joining, at: lastIndex + 1)
        reorder(&ordered)
        templateExerciseDraftsValue = ordered
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
}
