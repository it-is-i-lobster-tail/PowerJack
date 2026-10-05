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
            exerciseCounts: templateWorkouts.map { $0.templateExercises.count }
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
