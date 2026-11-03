//
//  TemplateTypeTests.swift
//  PowerJackTests
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct TemplateTypeTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("Sections are named Hypertrophy, Strength and PowerJack, in that order")
    func sectionNames() {
        #expect(TemplateType.allCases.map(\.name) == ["Hypertrophy", "Strength", "PowerJack"])
        #expect(TemplateType.allCases.map(\.rawValue) == ["hypertrophy", "strength", "powerjack"])
    }

    @Test("The middle section name sits on the screen's horizontal center")
    func middleSectionIsCentered() async throws {
        let screen = try await HostedView(TemplateProgramListView().modelContainer(container))
        defer { screen.close() }

        let middle = try #require(screen.frame(of: TemplateType.strength.name), "\(screen.labels)")
        #expect(abs(middle.midX - screen.window.bounds.midX) < 1)
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

    @Test("Changing a template's type saves the new type")
    func draftChangesType() throws {
        let template = TemplateProgram(templateName: "Heavy", workoutsPerWeek: 2, templateMuscleFocus: [.quads], templateType: .strength)
        try container.mainContext.insertAndSave(template)

        var edit = TemplateProgramDraft(templateProgram: template)
        edit.templateType = .powerJack
        #expect(edit.apply(to: template))
        #expect(template.templateType == .powerJack)
    }

    @Test("A new template from the Strength section starts as Strength")
    func newTemplateDefaultsToSection() async throws {
        UserDefaults.standard.set(TemplateType.strength.rawValue, forKey: TemplateType.selectionKey)
        defer { UserDefaults.standard.removeObject(forKey: TemplateType.selectionKey) }
        let container = HostedView.makeStore()
        let screen = try await HostedView(TemplateProgramListView().modelContainer(container))
        defer { screen.close() }

        #expect(await screen.tap("Add", settleFor: .milliseconds(800)), "\(screen.labels)")
        let type = try #require(screen.label(startingWith: "Type"), "\(screen.labels)")
        #expect(type.contains("Strength"), "\(type)")
    }

    @Test("Picking a type in the template detail saves it and moves the Templates list to it")
    func detailChangesType() async throws {
        defer { UserDefaults.standard.removeObject(forKey: TemplateType.selectionKey) }
        let container = HostedView.makeStore()
        let template = TemplateProgram(templateName: "Pull Days", workoutsPerWeek: 2, templateMuscleFocus: [.back])
        try container.mainContext.insertAndSave(template)
        let screen = try await HostedView(
            NavigationStack { TemplateProgramDetailView(templateProgram: template) }
                .modelContainer(container)
        )
        defer { screen.close() }

        let type = try #require(screen.label(startingWith: "Type"), "\(screen.labels)")
        await screen.tap(type, settleFor: .milliseconds(800))
        #expect(await screen.waitUntil { screen.contains(TemplateType.powerJack.name) }, "\(screen.labels)")
        await screen.tap(TemplateType.powerJack.name, settleFor: .milliseconds(800))

        #expect(template.templateType == .powerJack)
        #expect(!container.mainContext.hasChanges)
        #expect(UserDefaults.standard.string(forKey: TemplateType.selectionKey) == TemplateType.powerJack.rawValue)
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
