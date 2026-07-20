//
//  TemplateProgramDraft.swift
//  PowerJack
//
//  Created by trogdor on 7/19/26.
//

import Foundation
import SwiftUI

struct TemplateProgramDraft {
    static let maximumNameLength = 30
    static let minimumWorkoutsPerWeek = 2
    static let maximumWorkoutsPerWeek = 6
    static let maximumFocusMuscles = 4

    var templateName: String
    var workoutsPerWeek: Int?
    var templateWorkoutDraftsValue: [TemplateWorkoutDraft]
    var templateMuscleFocusValue: [Muscle]

    init() {
        self.templateName = ""
        self.workoutsPerWeek = nil
        self.templateWorkoutDraftsValue = []
        self.templateMuscleFocusValue = []
    }

    var canSave: Bool {
        guard let workoutsPerWeek else { return false }

        return (1...Self.maximumNameLength).contains(trimmedName.count) &&
        (Self.minimumWorkoutsPerWeek...Self.maximumWorkoutsPerWeek).contains(workoutsPerWeek) &&
        templateWorkoutDrafts.count == workoutsPerWeek &&
        templateWorkoutDrafts.allSatisfy(\.canSave) &&
        (1...Self.maximumFocusMuscles).contains(templateMuscleFocus.count)
    }

    private var trimmedName: String {
        templateName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

//
// Public Accessors
//
extension TemplateProgramDraft {
    var templateWorkoutDrafts: [TemplateWorkoutDraft] {
        templateWorkoutDraftsValue.sorted {
            ($0.order ?? .max) < ($1.order ?? .max)
        }
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
}

//
// Mutations
//
extension TemplateProgramDraft {
    func removingConfiguredWorkouts(for count: Int) -> Bool {
        guard count < templateWorkoutDrafts.count else { return false }

        return templateWorkoutDrafts
            .dropFirst(count)
            .contains { !$0.templateExerciseDrafts.isEmpty }
    }

    mutating func setWorkoutsPerWeek(_ count: Int) {
        guard (Self.minimumWorkoutsPerWeek...Self.maximumWorkoutsPerWeek).contains(count) else {
            return
        }

        workoutsPerWeek = count

        while templateWorkoutDraftsValue.count < count {
            _ = addTemplateWorkoutDraft()
        }

        if templateWorkoutDraftsValue.count > count {
            templateWorkoutDraftsValue = Array(templateWorkoutDrafts.prefix(count))
        }

        reorderWorkouts()
    }

    @discardableResult
    private mutating func addTemplateWorkoutDraft() -> TemplateWorkoutDraft {
        let newTemplateWorkoutDraft = TemplateWorkoutDraft(
            order: templateWorkoutDraftsValue.count
        )
        templateWorkoutDraftsValue.append(newTemplateWorkoutDraft)
        return newTemplateWorkoutDraft
    }

    mutating func moveTemplateWorkouts(from source: IndexSet, to destination: Int) {
        var ordered = templateWorkoutDrafts

        guard destination >= 0, destination <= ordered.count else { return }
        guard source.allSatisfy({ ordered.indices.contains($0) }) else { return }

        ordered.move(fromOffsets: source, toOffset: destination)
        templateWorkoutDraftsValue = ordered
        reorderWorkouts()
    }

    func makeTemplateProgram() -> TemplateProgram? {
        guard canSave,
              let workoutsPerWeek
        else {
            return nil
        }

        let templateProgram = TemplateProgram(
            templateName: trimmedName,
            workoutsPerWeek: workoutsPerWeek,
            templateMuscleFocus: templateMuscleFocus
        )

        templateProgram.templateWorkoutsValue = templateWorkoutDrafts.compactMap { workoutDraft in
            guard let order = workoutDraft.order else { return nil }

            let templateWorkout = TemplateWorkout(order: order)
            templateWorkout.templateExercisesValue = workoutDraft.templateExerciseDrafts.compactMap { exerciseDraft in
                guard let exercise = exerciseDraft.exercise,
                      let exerciseOrder = exerciseDraft.order
                else {
                    return nil
                }

                return TemplateExercise(
                    exercise: exercise,
                    order: exerciseOrder
                )
            }
            return templateWorkout
        }

        guard templateProgram.templateWorkouts.count == workoutsPerWeek,
              templateProgram.templateWorkouts.allSatisfy({ !$0.templateExercises.isEmpty })
        else {
            return nil
        }

        return templateProgram
    }

    private mutating func reorderWorkouts() {
        templateWorkoutDraftsValue.sort {
            ($0.order ?? .max) < ($1.order ?? .max)
        }

        for index in templateWorkoutDraftsValue.indices {
            templateWorkoutDraftsValue[index].order = index
        }
    }
}
