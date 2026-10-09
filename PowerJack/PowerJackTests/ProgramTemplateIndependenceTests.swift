//
//  ProgramTemplateIndependenceTests.swift
//  PowerJackTests
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ProgramTemplateIndependenceTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("A program keeps its schedule after its template drops to fewer days")
    func scheduleSurvivesTemplateEdit() throws {
        let template = try makeTemplate(workoutsPerWeek: 3)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        program.start()

        try editTemplate(template, workoutsPerWeek: 2, name: "Renamed", focus: [.quads])

        #expect(program.workoutsPerWeek == 3)
        #expect(program.totalWorkouts == 6)
        #expect(program.templateName == "Original")
        #expect(program.templateMuscleFocus == [.back])
        #expect(program.programWeeks.first?.workouts.count == 3)
    }

    @Test("A program reaches 100% after all six workouts, even after its template changed")
    func progressSurvivesTemplateEdit() throws {
        let template = try makeTemplate(workoutsPerWeek: 3)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        program.start()

        try editTemplate(template, workoutsPerWeek: 2, name: "Original", focus: [.back])

        var finished = 0
        while let workout = program.nextWorkout {
            // Mix completed and skipped workouts. Both count toward progress.
            if finished.isMultiple(of: 2) {
                workout.startAndCascade()
                program.finishWorkout(workout)
            } else {
                program.skipWorkout(workout)
            }
            finished += 1
        }

        #expect(finished == 6)
        #expect(program.programWeeks.map(\.workouts.count) == [3, 3])
        #expect(program.workoutsFinished == 6)
        #expect(program.percentFinished == 100)
        #expect(program.status == .complete)
    }

    @Test("Programs saved before the copy existed read their days per week from week 1")
    func legacyProgramFallsBackToWeekOne() throws {
        let template = try makeTemplate(workoutsPerWeek: 3)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        // Simulate a row stored before the program kept its own copy.
        program.workoutsPerWeekValue = 0
        program.templateNameValue = ""
        program.templateMuscleFocusValue = []

        try editTemplate(template, workoutsPerWeek: 2, name: "Renamed", focus: [.quads])

        #expect(program.workoutsPerWeek == 3)
        #expect(program.totalWorkouts == 6)
        #expect(program.templateName == "Renamed")
    }

    // MARK: Helpers

    private func makeTemplate(workoutsPerWeek: Int) throws -> TemplateProgram {
        let exercise = Exercise(
            exerciseName: "Row",
            exerciseEquipment: .cable,
            primaryMuscleFocus: .back
        )
        container.mainContext.insert(exercise)
        let template = TemplateProgram(
            templateName: "Original",
            workoutsPerWeek: workoutsPerWeek,
            templateMuscleFocus: [.back]
        )
        for _ in 0..<workoutsPerWeek {
            template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        }
        try container.mainContext.insertAndSave(template)
        return template
    }

    /// Edits the template the same way the template form does.
    private func editTemplate(
        _ template: TemplateProgram,
        workoutsPerWeek: Int,
        name: String,
        focus: [Muscle]
    ) throws {
        var draft = TemplateProgramDraft(templateProgram: template)
        draft.workoutsPerWeek = workoutsPerWeek
        draft.templateName = name
        draft.templateMuscleFocus = focus
        #expect(draft.apply(to: template))
        try container.mainContext.save()
        #expect(template.workoutsPerWeek == workoutsPerWeek)
        #expect(template.templateWorkouts.count == workoutsPerWeek)
    }
}
