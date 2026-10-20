//
//  TemplateTypeTests.swift
//  PowerJackTests
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct TemplateTypeTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("Sections are named Build, Strengthen and PowerJack, in that order")
    func sectionNames() {
        #expect(TemplateType.allCases.map(\.name) == ["Build", "Strengthen", "PowerJack"])
        #expect(TemplateType.allCases.map(\.rawValue) == ["hypertrophy", "strength", "powerjack"])
    }

    @Test("A new template takes its section's type, and editing it keeps the type")
    func draftKeepsType() throws {
        let exercise = Exercise(exerciseName: "Squat", exerciseEquipment: .barbell, primaryMuscleFocus: .quads)
        container.mainContext.insert(exercise)

        var draft = TemplateProgramDraft(templateType: .strength)
        draft.templateName = "Heavy"
        let template = try #require(try draft.insertNewTemplate(into: container.mainContext))
        #expect(template.templateType == .strength)

        var edit = TemplateProgramDraft(templateProgram: template)
        edit.templateName = "Heavier"
        #expect(edit.apply(to: template))
        #expect(template.templateType == .strength)
    }

    @Test("A program keeps the type it started with after its template changes")
    func programCopiesType() throws {
        let template = TemplateProgram(
            templateName: "Jacked",
            workoutsPerWeek: 2,
            templateMuscleFocus: [.chest],
            templateType: .powerJack
        )
        try container.mainContext.insertAndSave(template)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try container.mainContext.insertAndSave(program)

        template.templateType = .strength
        try container.mainContext.save()

        #expect(program.templateType == .powerJack)
    }

    @Test("Every type progresses with today's rules for now")
    func sharedProgressionRules() {
        let input = ProgressionInput(
            current: ProgressionHistory(
                programWeek: 1,
                status: .complete,
                pain: LevelOfPain.none,
                effort: .easy,
                sets: [ProgressionSet(actualReps: 11, actualWeightTenthsPounds: 1000, status: .complete)]
            ),
            exercise: ProgressionExerciseInfo(
                minReps: 6,
                maxReps: 12,
                primaryMuscle: .chest,
                secondaryMuscles: [],
                repsOnly: false
            ),
            focusMuscles: [],
            programLengthWeeks: 4,
            currentWeekMuscleSetCredits: [:]
        )
        let expected = ProgressionEngine.nextPrescription(input)
        for type in TemplateType.allCases {
            #expect(type.progressionRules(input) == expected, "\(type)")
        }
    }
}
