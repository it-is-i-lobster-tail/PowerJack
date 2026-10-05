//
//  TemplateProgram.swift
//  PowerJack
//
//  Created by Brendon on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class TemplateProgram {
    var catalogID: String? = nil
    var templateName: String = ""
    var workoutsPerWeek: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \TemplateWorkout.templateProgramValue)
    var templateWorkoutsValue: [TemplateWorkout]? = []
    var templateMuscleFocusValue: [Muscle] = []
    // Programs started from this template. Kept so CloudKit has both sides of the link.
    var programsValue: [Program]? = []
    // Rows stored before this field existed read as the oldest, so catalog dedupe keeps them.
    var createdAtValue: Date = Date.distantPast
    // Hidden from the template list but kept, so programs started from it keep their name and
    // the catalog seed doesn't bring a deleted built-in template back.
    var hiddenValue: Bool = false

    init(
        templateName: String,
        workoutsPerWeek: Int,
        templateMuscleFocus: [Muscle]
    ) {
        self.templateName = templateName
        self.workoutsPerWeek = max(0, workoutsPerWeek)
        self.templateWorkoutsValue = []
        self.templateMuscleFocusValue = templateMuscleFocus
        self.createdAtValue = .now
    }
}

//
// Public Accesors
//
extension TemplateProgram {
    // Template Workouts
    var templateWorkouts: [TemplateWorkout] { (templateWorkoutsValue ?? []).sorted(byOrder: \.order) }
    // Template Muscle Focus
    var templateMuscleFocus: [Muscle] {
        get {
            templateMuscleFocusValue.sorted {
                $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending
            }
        }
        set {
            if newValue.count <= 4 {
                templateMuscleFocusValue = newValue
            }
        }
    }
    /// True until the template has a name, focus muscles, workouts per week and an exercise
    /// on every day. Drafts are saved but can't start a program.
    var draft: Bool {
        Self.isDraft(
            name: templateName,
            muscleFocus: templateMuscleFocusValue,
            workoutsPerWeek: workoutsPerWeek,
            // Rows whose exercise is missing (deleted, or not synced yet) don't count.
            exerciseCounts: templateWorkouts.map { $0.templateExercises.compactMap(\.exercise).count }
        )
    }
    /// The name shown in lists, marked while the template is still a draft.
    var displayName: String {
        let trimmed = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Untitled" : trimmed
        return draft ? "(Draft) \(name)" : name
    }

    /// The one draft rule, shared with `TemplateProgramDraft` so the form and the list agree.
    static func isDraft(
        name: String,
        muscleFocus: [Muscle],
        workoutsPerWeek: Int,
        exerciseCounts: [Int]
    ) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        muscleFocus.isEmpty ||
        workoutsPerWeek < 1 ||
        exerciseCounts.count < workoutsPerWeek ||
        exerciseCounts.prefix(workoutsPerWeek).contains(0)
    }
}

//
// Mutations
//
extension TemplateProgram {
    
    @discardableResult
    func addTemplateWorkout() -> TemplateWorkout {
        let new = TemplateWorkout(
            order: templateWorkouts.count
        )
        templateWorkoutsValue = (templateWorkoutsValue ?? []) + [new]
        return new
    }
    
    /// Removes the template from the list. It's only truly deleted when nothing still needs it.
    func delete() {
        guard catalogID == nil, (programsValue ?? []).isEmpty else {
            hiddenValue = true
            return
        }
        modelContext?.delete(self)
    }

    func clearAllTemplateWorkoutsValue() -> Void {
        // Delete the old rows so rebuilding the workouts doesn't leave orphans behind.
        // Deleting a workout cascades to its exercises.
        let workouts = templateWorkouts
        templateWorkoutsValue = []
        for workout in workouts {
            modelContext?.delete(workout)
        }
    }
}
