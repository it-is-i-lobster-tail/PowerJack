//
//  TemplateProgramDraft.swift
//  PowerJack
//
//  Created by trogdor on 7/19/26.
//

import Foundation
import SwiftData
import SwiftUI

struct TemplateProgramDraft {
    static let maximumNameLength = 50
    static let minimumWorkoutsPerWeek = 2
    static let maximumWorkoutsPerWeek = 6
    static let maximumFocusMuscles = 4
    /// Saved in place of an empty name, so an unnamed template still has one.
    static let defaultName = "New"

    var templateName: String
    var workoutsPerWeekValue: Int?
    var templateMuscleFocusValue: [Muscle]
    var templateWorkoutDraftsValue: [TemplateWorkoutDraft]

    init(
        templateProgram: TemplateProgram? = nil
    ) {
        self.templateName = templateProgram?.templateName ?? ""
        // Drafts store 0 when no count was picked yet.
        self.workoutsPerWeekValue = templateProgram.flatMap { $0.workoutsPerWeek > 0 ? $0.workoutsPerWeek : nil }
        self.templateMuscleFocusValue = templateProgram?.templateMuscleFocus ?? []
        self.templateWorkoutDraftsValue = []
        
        if let templateWorkouts = templateProgram?.templateWorkouts {
            for templateWorkout in templateWorkouts {
                addTemplateWorkoutDraft(
                    enabled: false,
                    templateExercises: templateWorkout.templateExercises
                )
            }
        }
    
        if templateWorkoutDraftsValue.count < TemplateProgramDraft.maximumWorkoutsPerWeek {
            let delta = TemplateProgramDraft.maximumWorkoutsPerWeek - templateWorkoutDraftsValue.count
            for _ in 0..<delta {
                addTemplateWorkoutDraft(enabled: false)
            }
        }
        if let workoutsPerWeekValue {
            updateWorkoutsPerWeek(newValue: workoutsPerWeekValue)
        }
    }

    /// Unfinished templates still save, as drafts. Only an empty form has nothing to keep.
    var canSave: Bool {
        trimmedName.count <= Self.maximumNameLength && hasContent
    }

    /// Matches `TemplateProgram.draft` for the template this would save.
    var isDraft: Bool {
        TemplateProgram.isDraft(
            name: savedName,
            muscleFocus: templateMuscleFocus,
            workoutsPerWeek: workoutsPerWeek ?? 0,
            exerciseCounts: templateWorkoutDrafts.map(\.templateExerciseDrafts.count)
        )
    }

    private var hasContent: Bool {
        !trimmedName.isEmpty ||
        !templateMuscleFocus.isEmpty ||
        workoutsPerWeek != nil
    }

    private var trimmedName: String {
        templateName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedName: String {
        trimmedName.isEmpty ? Self.defaultName : trimmedName
    }
    
    func makeTemplate() -> TemplateProgram? {
        guard canSave else { return nil }

        let newTemplateProgram = TemplateProgram(
            templateName: savedName,
            workoutsPerWeek: workoutsPerWeek ?? 0,
            templateMuscleFocus: templateMuscleFocus
        )

        for templateWorkoutDraft in templateWorkoutDrafts {
            let newTemplateWorkout = newTemplateProgram.addTemplateWorkout()
            for templateExerciseDraft in templateWorkoutDraft.templateExerciseDrafts {
                newTemplateWorkout.addTemplateExercise(
                    exercise: templateExerciseDraft.exercise
                )
            }
        }
        return newTemplateProgram
    }
    
    /// Inserts and saves a new template. A new "New" replaces the old one, so unnamed
    /// templates don't pile up.
    func insertNewTemplate(into context: ModelContext) throws -> TemplateProgram? {
        guard let newTemplateProgram = makeTemplate() else { return nil }

        if newTemplateProgram.templateName == Self.defaultName {
            let name = Self.defaultName
            let replaced = try context.fetch(FetchDescriptor<TemplateProgram>(
                predicate: #Predicate { $0.templateName == name && !$0.hiddenValue }
            ))
            for templateProgram in replaced where templateProgram.catalogID == nil {
                templateProgram.delete()
            }
        }

        try context.insertAndSave(newTemplateProgram)
        return newTemplateProgram
    }

    @discardableResult
    func apply(to templateProgram: TemplateProgram) -> Bool {
        guard canSave else { return false }

        templateProgram.templateName = savedName
        templateProgram.workoutsPerWeek = workoutsPerWeek ?? 0
        templateProgram.templateMuscleFocus = templateMuscleFocus
        // Rebuild the workouts only when their exercises changed, so renaming stays cheap.
        guard workoutLayout != Self.workoutLayout(of: templateProgram) else { return true }
        templateProgram.clearAllTemplateWorkoutsValue()

        for templateWorkoutDraft in templateWorkoutDrafts {
            let newTemplateWorkout = templateProgram.addTemplateWorkout()
            for templateExerciseDraft in templateWorkoutDraft.templateExerciseDrafts {
                newTemplateWorkout.addTemplateExercise(
                    exercise: templateExerciseDraft.exercise
                )
            }
        }

        return true
    }
}

//
// Change Tracking
//
extension TemplateProgramDraft {
    /// Everything the user can edit, so any change can trigger an autosave.
    struct Snapshot: Equatable {
        let name: String
        let workoutsPerWeek: Int?
        let focus: [Muscle]
        let workoutLayout: [[PersistentIdentifier]]
    }

    var snapshot: Snapshot {
        Snapshot(
            name: templateName,
            workoutsPerWeek: workoutsPerWeek,
            focus: templateMuscleFocus,
            workoutLayout: workoutLayout
        )
    }

    /// The exercises in each enabled workout, in order.
    private var workoutLayout: [[PersistentIdentifier]] {
        templateWorkoutDrafts.map { $0.templateExerciseDrafts.map(\.exercise.persistentModelID) }
    }

    private static func workoutLayout(of templateProgram: TemplateProgram) -> [[PersistentIdentifier]] {
        templateProgram.templateWorkouts.map { $0.templateExercises.compactMap(\.exercise?.persistentModelID) }
    }
}

//
// Public Accessors
//
extension TemplateProgramDraft {
    var templateWorkoutDrafts: [TemplateWorkoutDraft] {
        templateWorkoutDraftsValue.filter(\.enabled).sorted { $0.order < $1.order }
    }

    var templateMuscleFocus: [Muscle] {
        get {
            templateMuscleFocusValue.sorted {
                $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending
            }
        }
        set {
            guard newValue.count <= Self.maximumFocusMuscles else { return }
            templateMuscleFocusValue = newValue
        }
    }
    
    var workoutsPerWeek: Int? {
        get {
            workoutsPerWeekValue
        }
        
        set {
            guard let value = newValue else {
                workoutsPerWeekValue = nil
                return
            }

            guard (
                Self.minimumWorkoutsPerWeek...Self.maximumWorkoutsPerWeek
            ).contains(value) else {
                return
            }

            updateWorkoutsPerWeek(newValue: value)
            workoutsPerWeekValue = value
        }
    }
}

//
// Mutations
//
extension TemplateProgramDraft {
    
    private mutating func updateWorkoutsPerWeek(newValue: Int) {
        for index in templateWorkoutDraftsValue.indices {
            templateWorkoutDraftsValue[index].enabled = templateWorkoutDraftsValue[index].order < newValue
        }
    }

    @discardableResult
    private mutating func addTemplateWorkoutDraft(
        enabled: Bool,
        templateExercises: [TemplateExercise]? = nil
    ) -> TemplateWorkoutDraft {
        let newTemplateWorkoutDraft = TemplateWorkoutDraft(
            enabled: enabled,
            order: templateWorkoutDraftsValue.count,
            templateExercises: templateExercises
        )
        templateWorkoutDraftsValue.append(newTemplateWorkoutDraft)
        return newTemplateWorkoutDraft
    }
}
