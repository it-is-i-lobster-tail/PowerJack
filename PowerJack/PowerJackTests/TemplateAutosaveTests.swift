//
//  TemplateAutosaveTests.swift
//  PowerJackTests
//
//  Template edits save as they happen, even on a screen pushed over the template,
//  so leaving with the section switcher never loses them.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct TemplateAutosaveTests {
    @Test("Picking focus muscles on the pushed screen saves the template before going back")
    func editSavesOnPushedScreen() async throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        let template = TemplateProgram(templateName: "Pull Days", workoutsPerWeek: 2, templateMuscleFocus: [.back])
        container.mainContext.insert(template)
        try container.mainContext.save()

        let screen = try await HostedView(
            NavigationStack { TemplateProgramDetailView(templateProgram: template) }
                .modelContainer(container)
        )
        defer { screen.close() }

        let focusLink = try #require(screen.label(startingWith: "Focus Muscles"))
        await screen.tap(focusLink)
        #expect(await screen.waitUntil { screen.contains("Biceps") })
        await screen.tap("Biceps")

        #expect(template.templateMuscleFocus == [.back, .biceps])
        #expect(!container.mainContext.hasChanges)
    }

    @Test("An exercise added in the builder is saved when the switcher leaves Templates")
    func builderEditSurvivesSwitcher() async throws {
        let container = PowerJackSeed.makeInMemoryContainer()
        try ExerciseCatalog.seed(in: container.mainContext)
        let template = TemplateProgram(templateName: "Pull Days", workoutsPerWeek: 2, templateMuscleFocus: [.back])
        container.mainContext.insert(template)
        try container.mainContext.save()

        let screen = try await HostedView(
            PowerJackRootView()
                .modelContainer(container)
                .environment(PowerJackStore(inMemory: true))
        )
        defer { screen.close() }

        await screen.tap("Templates", settleFor: .milliseconds(800))
        let row = try #require(screen.label(startingWith: "(Draft) Pull Days"), "\(screen.labels)")
        await screen.tap(row, settleFor: .milliseconds(800))
        let build = try #require(screen.label(startingWith: "Build Workouts"), "\(screen.labels)")
        await screen.tap(build, settleFor: .milliseconds(800))
        #expect(await screen.tap("Add", settleFor: .milliseconds(800)), "\(screen.labels)")
        let bench = try #require(screen.label(startingWith: "Barbell Bench Press"), "\(screen.labels)")
        await screen.tap(bench, settleFor: .milliseconds(800))
        #expect(await screen.waitUntil { !screen.contains("Close") }, "\(screen.labels)")

        await screen.tap("Programs", settleFor: .milliseconds(800))
        #expect(screen.contains("My Programs"), "\(screen.labels)")

        let day1 = template.templateWorkouts.first?.templateExercises.compactMap(\.exercise?.exerciseName)
        #expect(day1 == ["Barbell Bench Press"])
        #expect(!container.mainContext.hasChanges)
    }

    @Test("A new template is created by the first edit on a pushed screen")
    func newTemplateSavesOnPushedScreen() async throws {
        let container = PowerJackSeed.makeInMemoryContainer()

        let screen = try await HostedView(
            NavigationStack { TemplateProgramNew() }
                .modelContainer(container)
        )
        defer { screen.close() }

        let focusLink = try #require(screen.label(startingWith: "Focus Muscles"))
        await screen.tap(focusLink)
        #expect(await screen.waitUntil { screen.contains("Biceps") })
        await screen.tap("Biceps")

        let templates = try container.mainContext.fetch(FetchDescriptor<TemplateProgram>())
        #expect(templates.map(\.templateName) == [TemplateProgramDraft.defaultName])
        #expect(templates.first?.templateMuscleFocus == [.biceps])
    }
}
