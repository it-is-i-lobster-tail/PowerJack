//
//  TemplateDraftTests.swift
//  PowerJackTests
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct TemplateDraftTests {
    @Test("A template is a draft until it has a name, focus, workouts per week and exercises every day")
    func draftRule() {
        let row = makeExercise()
        let template = makeTemplate(exercise: row)
        #expect(!template.draft)
        #expect(template.displayName == "Pull Days")

        template.templateName = "  "
        #expect(template.draft)
        #expect(template.displayName == "(Draft) Untitled")
        template.templateName = "Pull Days"

        template.templateMuscleFocus = []
        #expect(template.draft)
        template.templateMuscleFocus = [.back]

        template.workoutsPerWeek = 0
        #expect(template.draft)
        template.workoutsPerWeek = 2

        // An empty day is exactly what used to leave a program with nothing to do.
        template.templateWorkouts[1].templateExercisesValue = []
        #expect(template.draft)
        #expect(template.displayName == "(Draft) Pull Days")
        template.templateWorkouts[1].addTemplateExercise(exercise: row)
        #expect(!template.draft)

        // More days than workouts is a draft too.
        template.workoutsPerWeek = 3
        #expect(template.draft)
    }

    @Test("An unfinished template still saves, as a draft, and the form agrees")
    func unfinishedTemplateSavesAsDraft() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext

        var draft = TemplateProgramDraft()
        #expect(!draft.canSave, "An empty form has nothing to keep")

        draft.templateName = "Push"
        #expect(draft.canSave)
        #expect(draft.isDraft)

        let template = try #require(draft.makeTemplate())
        try context.insertAndSave(template)
        #expect(template.draft)
        #expect(template.workoutsPerWeek == 0)
        #expect(template.displayName == "(Draft) Push")

        // Reopening it keeps "workouts per week" unpicked rather than 0.
        #expect(TemplateProgramDraft(templateProgram: template).workoutsPerWeek == nil)
    }

    @Test("Editing saves an empty day, and finishing it clears the draft")
    func editingClearsDraftOnceComplete() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext
        let row = makeExercise()
        context.insert(row)
        let template = makeTemplate(exercise: row)
        try context.insertAndSave(template)

        var draft = TemplateProgramDraft(templateProgram: template)
        draft.workoutsPerWeek = 3
        #expect(draft.isDraft)
        #expect(draft.apply(to: template))
        try context.save()
        #expect(template.workoutsPerWeek == 3)
        #expect(template.draft)

        _ = draft.templateWorkoutDraftsValue[2].addTemplateExerciseDraft(exercise: row)
        #expect(!draft.isDraft)
        #expect(draft.apply(to: template))
        try context.save()
        #expect(!template.draft)
        #expect(template.displayName == "Pull Days")
    }

    @Test("Exercise rows that lost their exercise don't count, so the template is a draft")
    func missingExercisesMakeADraft() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext
        let row = makeExercise()
        context.insert(row)
        let template = makeTemplate(exercise: row)
        try context.insertAndSave(template)
        #expect(!template.draft)

        // Rows stay behind (nullify) but would build a program with no exercises.
        context.delete(row)
        try context.save()
        #expect(template.templateWorkouts.allSatisfy { $0.templateExercises.count == 1 })
        #expect(template.draft)
        #expect(!ProgramDraft(programLengthWeeks: 4, templateProgram: template).canSave)
    }

    @Test("A template saved without a name is called New")
    func unnamedTemplateIsCalledNew() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext

        var draft = TemplateProgramDraft()
        draft.workoutsPerWeek = 3
        let template = try #require(try draft.insertNewTemplate(into: context))
        #expect(template.templateName == TemplateProgramDraft.defaultName)
        #expect(template.displayName == "(Draft) New")

        // Clearing the name while editing falls back to New too.
        var edit = TemplateProgramDraft(templateProgram: template)
        edit.templateName = "Legs"
        #expect(edit.apply(to: template))
        edit.templateName = "  "
        #expect(edit.apply(to: template))
        #expect(template.templateName == "New")
    }

    @Test("A new New template replaces the old one, but other names are kept")
    func newTemplateReplacesOldNew() throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let context = container.mainContext

        var unnamed = TemplateProgramDraft()
        unnamed.workoutsPerWeek = 2
        let first = try #require(try unnamed.insertNewTemplate(into: context))

        var named = TemplateProgramDraft()
        named.templateName = "Push"
        let push = try #require(try named.insertNewTemplate(into: context))

        let second = try #require(try unnamed.insertNewTemplate(into: context))

        let visible = try context.fetch(FetchDescriptor<TemplateProgram>(
            predicate: #Predicate { !$0.hiddenValue }
        ))
        #expect(Set(visible.map(\.persistentModelID)) == [push.persistentModelID, second.persistentModelID])
        #expect(first.modelContext == nil || first.hiddenValue)

        // A second Push is the user's own name, so the first one stays.
        _ = try named.insertNewTemplate(into: context)
        let pushes = try context.fetch(FetchDescriptor<TemplateProgram>(
            predicate: #Predicate { $0.templateName == "Push" }
        ))
        #expect(pushes.count == 2)
    }

    @Test("Draft templates can't start a program")
    func draftTemplateCantStartProgram() {
        let template = makeTemplate(exercise: makeExercise())
        template.templateWorkouts[0].templateExercisesValue = []

        let draft = ProgramDraft(programLengthWeeks: 4, templateProgram: template)
        #expect(!draft.canSave)
        #expect(draft.makeProgram() == nil)
    }

    private func makeExercise() -> Exercise {
        Exercise(exerciseName: "Row", exerciseEquipment: .cable, primaryMuscleFocus: .back)
    }

    private func makeTemplate(exercise: Exercise) -> TemplateProgram {
        let template = TemplateProgram(
            templateName: "Pull Days",
            workoutsPerWeek: 2,
            templateMuscleFocus: [.back]
        )
        for _ in 0..<2 {
            template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        }
        return template
    }
}
