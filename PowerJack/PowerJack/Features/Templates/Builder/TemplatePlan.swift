//
//  TemplatePlan.swift
//  PowerJack
//
//  What Build for Me makes: each day's exercises in order and the supersets among them. It stores
//  nothing; the lifter reviews it as an unsaved template draft.
//

import Foundation

struct TemplatePlan: Hashable, Sendable {
    static let maximumNameLength = 24

    /// Two exercises next to each other that share one rest.
    struct Superset: Hashable, Sendable {
        var first: String
        var second: String

        func contains(_ id: String) -> Bool { first == id || second == id }
    }

    struct Day: Hashable, Sendable {
        var exerciseIDs: [String] = []
        var supersets: [Superset] = []
    }

    var name: String
    var days: [Day]
}

extension TemplatePlan {
    /// The plan as an unsaved template draft, ready for the template builder. IDs with no exercise
    /// in `exercises` are left out.
    func makeDraft(for request: TemplateRequest, exercises: [Exercise]) -> TemplateProgramDraft {
        let exercisesByID = Dictionary(exercises.map { (StrengthLifts.key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        var draft = TemplateProgramDraft(templateType: request.type)
        draft.templateName = name
        draft.templateMuscleFocus = request.focus
        draft.workoutsPerWeek = days.count

        for (index, day) in days.enumerated() where draft.templateWorkoutDraftsValue.indices.contains(index) {
            var supersetIDs: [String: UUID] = [:]
            for superset in day.supersets {
                let id = UUID()
                supersetIDs[superset.first] = id
                supersetIDs[superset.second] = id
            }
            for id in day.exerciseIDs {
                guard let exercise = exercisesByID[id] else { continue }
                draft.templateWorkoutDraftsValue[index].addTemplateExerciseDraft(exercise: exercise, supersetID: supersetIDs[id])
            }
        }
        return draft
    }
}
