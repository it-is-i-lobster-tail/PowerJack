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

    /// The exercises in order after dropping the exercises with `ids` on `target`, or nil when nothing would change.
    /// Dropped onto a card, they join its superset. Dropped above or below it, they move there: a whole superset
    /// stays together, and exercises pulled out of one stand alone.
    func dropping(_ ids: [UUID], on target: TemplateExerciseBlock, at placement: StackPlacement) -> [TemplateExerciseDraft]? {
        let ids = Set(ids)
        let blocks = blocks
        guard let target = blocks.first(where: { $0.id == target.id }) else { return nil }
        let staying = target.exercises.filter { !ids.contains($0.id) }
        guard let first = staying.first, let last = staying.last else { return nil }

        var ordered = templateExerciseDrafts
        var moving = ordered.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return nil }
        ordered.removeAll { ids.contains($0.id) }

        let index: Int
        switch placement {
        case .onto:
            let supersetID = target.isSuperset ? (first.supersetID ?? UUID()) : UUID()
            let stayingIDs = Set(staying.map(\.id))
            for i in ordered.indices where stayingIDs.contains(ordered[i].id) {
                ordered[i].supersetID = supersetID
            }
            for i in moving.indices {
                moving[i].supersetID = supersetID
            }
            index = (ordered.firstIndex { $0.id == last.id } ?? ordered.count - 1) + 1
        case .before, .after:
            let isWholeSuperset = blocks.contains { $0.isSuperset && Set($0.exercises.map(\.id)) == ids }
            if !isWholeSuperset {
                for i in moving.indices {
                    moving[i].supersetID = nil
                }
            }
            let anchor = placement == .before ? first.id : last.id
            let anchorIndex = ordered.firstIndex { $0.id == anchor } ?? 0
            index = placement == .before ? anchorIndex : anchorIndex + 1
        }
        ordered.insert(contentsOf: moving, at: index)
        Self.reorder(&ordered)
        Self.clearLoneSupersets(in: &ordered)
        return ordered == templateExerciseDrafts ? nil : ordered
    }
}

/// Where an exercise card lands when it's dropped on another: above it, onto it to stack them, or below it.
enum StackPlacement: Equatable {
    case before, onto, after
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
        Self.reorder(&ordered)
        templateExerciseDraftsValue = ordered
        clearLoneSupersets()
    }

    mutating func moveTemplateExercises(from source: IndexSet, to destination: Int) {
        var ordered = templateExerciseDrafts

        guard destination >= 0, destination <= ordered.count else { return }
        guard source.allSatisfy({ ordered.indices.contains($0) }) else { return }

        ordered.move(fromOffsets: source, toOffset: destination)
        Self.reorder(&ordered)
        templateExerciseDraftsValue = ordered
        clearLoneSupersets()
    }

    /// Drops the exercises with `ids` on `target` (see `dropping(_:on:at:)`).
    mutating func drop(_ ids: [UUID], on target: TemplateExerciseBlock, at placement: StackPlacement) {
        guard let ordered = dropping(ids, on: target, at: placement) else { return }
        templateExerciseDraftsValue = ordered
    }

    /// Splits a superset back into exercises on their own.
    mutating func unstack(_ block: TemplateExerciseBlock) {
        let ids = Set(block.exercises.map(\.id))
        for index in templateExerciseDraftsValue.indices where ids.contains(templateExerciseDraftsValue[index].id) {
            templateExerciseDraftsValue[index].supersetID = nil
        }
    }

    private static func reorder(_ drafts: inout [TemplateExerciseDraft]) {
        for index in drafts.indices {
            drafts[index].order = index
        }
    }

    /// Only exercises next to each other share a superset, so an ID left on its own is cleared.
    private mutating func clearLoneSupersets() {
        var ordered = templateExerciseDrafts
        Self.clearLoneSupersets(in: &ordered)
        templateExerciseDraftsValue = ordered
    }

    /// `drafts` must be in order.
    private static func clearLoneSupersets(in drafts: inout [TemplateExerciseDraft]) {
        for index in drafts.indices {
            guard let supersetID = drafts[index].supersetID else { continue }
            let hasNeighbor = [index - 1, index + 1].contains { drafts.indices.contains($0) && drafts[$0].supersetID == supersetID }
            if !hasNeighbor {
                drafts[index].supersetID = nil
            }
        }
    }
}
