//
//  AppScreenTests.swift
//  PowerJackTests
//
//  Drives the app's other screens: settings, templates, exercises and starting a program.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct AppScreenTests {
    private let container: ModelContainer

    init() throws {
        container = PowerJackSeed.makeInMemoryContainer()
        try ExerciseCatalog.seed(in: container.mainContext)
        try TemplateCatalog.seed(in: container.mainContext)
    }

    @Test("Settings opens from the gear and toggles the rest timer options")
    func settings() async throws {
        let defaults = UserDefaults.standard
        let keys = [AppSettings.Key.inAppRestTimer, AppSettings.Key.restLiveActivity, AppSettings.Key.iCloudBackup]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: AppSettings.Key.inAppRestTimer)
        defaults.set(true, forKey: AppSettings.Key.restLiveActivity)

        let store = PowerJackStore(inMemory: true)
        let screen = try await HostedView(
            PowerJackRootView()
                .modelContainer(container)
                .environment(store)
        )
        defer { screen.close() }

        #expect(await screen.tap("Settings", settleFor: .milliseconds(800)), "\(screen.labels)")
        let inApp = try #require(screen.label(startingWith: "In-App Timer"), "\(screen.labels)")
        await screen.tap(inApp)
        #expect(defaults.bool(forKey: AppSettings.Key.inAppRestTimer) == false)
        let liveActivity = try #require(screen.label(startingWith: "Dynamic Island"))
        await screen.tap(liveActivity)
        #expect(defaults.bool(forKey: AppSettings.Key.restLiveActivity) == false)

        // In memory, turning backup on swaps the container without touching iCloud.
        let backup = try #require(screen.label(startingWith: "iCloud Backup"))
        let containerBefore = ObjectIdentifier(store.container)
        await screen.tap(backup)
        #expect(store.syncsWithICloud)
        #expect(ObjectIdentifier(store.container) != containerBefore)

        await screen.tap("Done", settleFor: .milliseconds(800))
        #expect(screen.label(startingWith: "In-App Timer") == nil)
    }

    @Test("Rest Between Sets opens a wheel that stays inside 0:30...5:00")
    func restBetweenSets() async throws {
        let defaults = UserDefaults.standard
        let key = RestLength.standard.secondsKey
        let saved = defaults.object(forKey: key)
        defer { defaults.set(saved, forKey: key) }
        defaults.set(295, forKey: key)

        let screen = try await HostedView(NavigationStack { RestBetweenSetsView() })
        defer { screen.close() }

        let row = try #require(screen.label(startingWith: "Standard"), "\(screen.labels)")
        await screen.tap(row, settleFor: .milliseconds(600))
        // Wheels are minutes, then seconds. 4:55 plus a minute snaps back to 5:00.
        #expect(await screen.adjust(at: 0, increment: true), "\(screen.labels)")
        #expect(defaults.integer(forKey: key) == 300)
        await screen.adjust(at: 1, increment: false)
        await screen.adjust(at: 0, increment: false)
        #expect(RestLength.range.contains(.seconds(defaults.integer(forKey: key))), "\(screen.labels)")
        #expect(defaults.integer(forKey: key) < 300, "\(screen.labels)")

        // Opening another length closes the first.
        let long = try #require(screen.label(startingWith: "Long"))
        await screen.tap(long, settleFor: .milliseconds(600))
        await screen.tap(long, settleFor: .milliseconds(600))
    }

    @Test("The bottom switcher moves between Programs and Templates")
    func switcher() async throws {
        let screen = try await HostedView(
            PowerJackRootView()
                .modelContainer(container)
                .environment(PowerJackStore(inMemory: true))
        )
        defer { screen.close() }

        await screen.tap("Templates", settleFor: .milliseconds(800))
        #expect(screen.contains("My Templates"), "\(screen.labels)")
        await screen.tap("Templates", settleFor: .milliseconds(500))
        await screen.tap("Programs", settleFor: .milliseconds(800))
        #expect(screen.contains("My Programs"), "\(screen.labels)")
    }

    @Test("Volume is empty until a workout is logged, then shows every muscle")
    func volume() async throws {
        let screen = try await HostedView(
            PowerJackRootView()
                .modelContainer(container)
                .environment(PowerJackStore(inMemory: true))
        )
        defer { screen.close() }

        await screen.tap("Volume", settleFor: .milliseconds(800))
        #expect(screen.contains("No workouts yet"), "\(screen.labels)")

        container.mainContext.insert(WorkoutLog(date: .now, setsByMuscle: [.chest: 8]))
        await screen.settle(.milliseconds(800))
        #expect(screen.contains("Chest"), "\(screen.labels)")
        #expect(screen.contains("Hamstrings"), "\(screen.labels)")
    }

    @Test("The template builder adds exercises from the catalog")
    func templateBuilderAddsExercise() async throws {
        let screen = try await HostedView(
            NavigationStack { BuilderHost() }.modelContainer(container)
        )
        defer { screen.close() }

        #expect(await screen.tap("Add", settleFor: .milliseconds(800)), "\(screen.labels)")
        let bench = try #require(screen.label(startingWith: "Barbell Bench Press"), "\(screen.labels)")
        await screen.tap(bench, settleFor: .milliseconds(800))
        #expect(screen.labels.contains { $0.hasPrefix("Barbell Bench Press") }, "\(screen.labels)")
        #expect(!screen.contains("Close"))
    }

    @Test("Template builder days change by tap only, so row swipes never flip the day")
    func templateBuilderDaysAreTapOnly() async throws {
        let screen = try await HostedView(
            NavigationStack { BuilderHost() }.modelContainer(container)
        )
        defer { screen.close() }

        #expect(screen.horizontalScrollViews.isEmpty, "A sideways pager would steal the rows' swipe actions")

        await screen.tap("Add", settleFor: .milliseconds(800))
        let bench = try #require(screen.label(startingWith: "Barbell Bench Press"), "\(screen.labels)")
        await screen.tap(bench, settleFor: .milliseconds(800))
        #expect(screen.labels.contains { $0.hasPrefix("Barbell Bench Press") }, "\(screen.labels)")

        await screen.tap("Day 2", settleFor: .milliseconds(600))
        #expect(!screen.labels.contains { $0.hasPrefix("Barbell Bench Press") }, "\(screen.labels)")
        #expect(screen.horizontalScrollViews.isEmpty)

        await screen.tap("Day 1", settleFor: .milliseconds(600))
        #expect(screen.labels.contains { $0.hasPrefix("Barbell Bench Press") }, "\(screen.labels)")
    }

    @Test("Browsing exercises opens the selected exercise's details")
    func browseExercises() async throws {
        let screen = try await HostedView(
            ExerciseSelectionView(navigationTitle: "Exercises").modelContainer(container)
        )
        defer { screen.close() }

        let curl = try #require(screen.label(startingWith: "Barbell Curl"), "\(screen.labels)")
        await screen.tap(curl, settleFor: .milliseconds(800))
        #expect(screen.contains("This exercise is included with PowerJack and cannot be edited."), "\(screen.labels)")
    }

    @Test("Picking a template from the list opens it, and selection mode returns it")
    func templateList() async throws {
        let browse = try await HostedView(TemplateProgramListView().modelContainer(container))
        let name = TemplateCatalog.entries[0].name
        let row = try #require(browse.label(startingWith: name), "\(browse.labels)")
        await browse.tap(row, settleFor: .milliseconds(800))
        #expect(browse.labels.count > 0)
        browse.close()

        let picked = SelectionResult()
        let select = try await HostedView(
            TemplateProgramListView(onSelect: { picked.template = $0 }).modelContainer(container)
        )
        defer { select.close() }
        let selectRow = try #require(select.label(startingWith: name), "\(select.labels)")
        await select.tap(selectRow, settleFor: .milliseconds(600))
        #expect(picked.template?.templateName == name)
    }

    @Test("New Program picks a template from the sheet")
    func newProgramTemplate() async throws {
        let screen = try await HostedView(
            NavigationPreviewHost(modelContainer: container) { ProgramNew() }
        )
        defer { screen.close() }

        let template = try #require(screen.label(startingWith: "Template"), "\(screen.labels)")
        await screen.tap(template, settleFor: .milliseconds(800))
        let name = TemplateCatalog.entries[1].name
        let row = try #require(screen.label(startingWith: name), "\(screen.labels)")
        await screen.tap(row, settleFor: .milliseconds(800))
        #expect(screen.labels.contains { $0.contains(name) }, "\(screen.labels)")
    }
}

@MainActor
final class SelectionResult {
    var template: TemplateProgram?
}

private struct BuilderHost: View {
    @State private var draft = TemplateProgramDraft()

    var body: some View {
        TemplateBuilder(draft: $draft)
    }
}
