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
        // Templates open on the section last picked, so start each test on Build.
        UserDefaults.standard.removeObject(forKey: TemplateType.selectionKey)
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

        #expect(await screen.selectTab("Settings", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(await screen.tap("Personalization", settleFor: .milliseconds(600)), "\(screen.labels)")
        let inApp = try #require(screen.label(startingWith: "In-App Timer"), "\(screen.labels)")
        await screen.tap(inApp)
        #expect(defaults.bool(forKey: AppSettings.Key.inAppRestTimer) == false)
        let liveActivity = try #require(screen.label(startingWith: "Dynamic Island"))
        await screen.tap(liveActivity)
        #expect(defaults.bool(forKey: AppSettings.Key.restLiveActivity) == false)

        // In memory, turning backup on swaps the container without touching iCloud.
        #expect(await screen.goBack())
        #expect(await screen.tap("Your Data", settleFor: .milliseconds(600)), "\(screen.labels)")
        let backup = try #require(screen.label(startingWith: "iCloud Backup"), "\(screen.labels)")
        let containerBefore = ObjectIdentifier(store.container!)
        await screen.tap(backup)
        #expect(store.syncsWithICloud)
        #expect(ObjectIdentifier(store.container!) != containerBefore)

        #expect(await screen.goBack())
        await screen.selectTab("Programs", settleFor: .milliseconds(800))
        #expect(await screen.waitUntil { !screen.contains("Personalization") }, "\(screen.labels)")
    }

    @Test("Switching iCloud Backup keeps Settings open on Your Data and the chosen section")
    func iCloudSwitchKeepsPlace() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: AppSettings.Key.iCloudBackup)
        defer { defaults.set(saved, forKey: AppSettings.Key.iCloudBackup) }

        // Wired like the app, so the new container reaches the screens.
        let store = PowerJackStore(inMemory: true)
        let screen = try await HostedView(PowerJackAppContent().environment(store))
        defer { screen.close() }

        await screen.selectTab("Templates", settleFor: .milliseconds(800))
        #expect(await screen.selectTab("Settings", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(await screen.tap("Your Data", settleFor: .milliseconds(600)), "\(screen.labels)")
        let backup = try #require(screen.label(startingWith: "iCloud Backup"), "\(screen.labels)")
        await screen.tap(backup, settleFor: .milliseconds(800))
        #expect(store.syncsWithICloud)
        #expect(screen.label(startingWith: "iCloud Backup") != nil, "Settings closed: \(screen.labels)")

        #expect(await screen.goBack())
        await screen.selectTab("Templates", settleFor: .milliseconds(800))
        #expect(screen.contains("My Templates"), "\(screen.labels)")
    }

    @Test("Switching iCloud Backup from the active program's page doesn't read the closed store")
    func iCloudSwitchFromProgramDetail() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: AppSettings.Key.iCloudBackup)
        defer { defaults.set(saved, forKey: AppSettings.Key.iCloudBackup) }

        // Launch reopens the active program's page, whose Start Workout button reads its workout.
        let store = PowerJackStore(inMemory: true)
        let context = store.container!.mainContext
        let exercise = Exercise(exerciseName: "Bench", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        context.insert(exercise)
        let template = TemplateProgram(templateName: "Switch Test", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        context.insert(template)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        try context.save()

        let screen = try await HostedView(PowerJackAppContent().environment(store))
        defer { screen.close() }
        #expect(screen.contains("Start Workout"), "\(screen.labels)")

        // Before the fix, the old page re-rendered on the new container and crashed here.
        #expect(await screen.selectTab("Settings", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(await screen.tap("Your Data", settleFor: .milliseconds(600)), "\(screen.labels)")
        let backup = try #require(screen.label(startingWith: "iCloud Backup"), "\(screen.labels)")
        let containerBefore = ObjectIdentifier(store.container!)
        await screen.tap(backup, settleFor: .milliseconds(800))
        #expect(store.syncsWithICloud)
        #expect(!store.isReplacingContainer)
        #expect(ObjectIdentifier(store.container!) != containerBefore)

        // The new in-memory store is empty, so the screens rebuilt from it show no program.
        #expect(await screen.goBack())
        await screen.selectTab("Programs", settleFor: .milliseconds(800))
        #expect(screen.contains("My Programs"), "\(screen.labels)")
        #expect(!screen.contains("Start Workout"), "\(screen.labels)")
    }

    @Test("Settings lists its groups, and each opens a page holding its settings")
    func settingsGroups() async throws {
        let screen = try await HostedView(
            NavigationStack { SettingsView() }
                .modelContainer(container)
                .environment(PowerJackStore(inMemory: true))
        )
        defer { screen.close() }

        // Each group, and a setting that must be on its page and nowhere else.
        let groups: [(group: String, setting: String)] = [
            ("Personalization", "In-App Timer"),
            ("My Gym", "Weight Unit"),
            ("Appearance", "Dark"),
            ("Your Data", "iCloud Backup"),
            ("Your Data", "Import from FitNotes"),
            ("FAQ", "What is PowerJack?"),
            ("Legal", "Privacy Policy"),
            ("Developer Tools", "Trace Logging"),
        ]
        // Importing lives in Your Data now, not in a group of its own.
        #expect(!screen.contains("Import"), "\(screen.labels)")
        for (_, setting) in groups {
            #expect(screen.label(startingWith: setting) == nil, "\(setting) is loose on the top page: \(screen.labels)")
        }
        for (group, setting) in groups {
            #expect(await screen.tap(group, settleFor: .milliseconds(600)), "\(group): \(screen.labels)")
            #expect(screen.label(startingWith: setting) != nil, "\(group) is missing \(setting): \(screen.labels)")
            #expect(await screen.goBack(), "\(group)")
            #expect(screen.contains("Personalization"), "\(group) didn't go back: \(screen.labels)")
        }
    }

    @Test("Weight Unit is a menu: one tap opens it and leaves the unit as it was")
    func weightUnitMenu() async throws {
        let defaults = UserDefaults.standard
        let key = AppSettings.Key.weightUnit
        let saved = defaults.object(forKey: key)
        defer { defaults.set(saved, forKey: key) }
        defaults.set(WeightUnit.pounds.rawValue, forKey: key)

        let screen = try await HostedView(NavigationStack { MyGymSettingsView() })
        defer { screen.close() }

        // The menu reads its name, then the full unit name.
        let menu = "Weight Unit, Pounds"
        #expect(screen.contains(menu), "\(screen.labels)")

        await screen.tap(menu, settleFor: .milliseconds(800))
        #expect(screen.labelsInAllWindows.contains("Kilograms"), "\(screen.labelsInAllWindows)")
        #expect(defaults.string(forKey: key) == WeightUnit.pounds.rawValue)
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
        // Down to 0 min snaps up to the 0:30 floor.
        for _ in 0 ..< 5 { await screen.adjust(at: 0, increment: false) }
        #expect(defaults.integer(forKey: key) == 30, "\(screen.labels)")

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

        await screen.selectTab("Templates", settleFor: .milliseconds(800))
        #expect(screen.contains("My Templates"), "\(screen.labels)")
        await screen.selectTab("Templates", settleFor: .milliseconds(500))
        await screen.selectTab("Programs", settleFor: .milliseconds(800))
        #expect(screen.contains("My Programs"), "\(screen.labels)")
    }

    @Test("Data shows two chart columns and opens the selected chart")
    func dataTab() async throws {
        // Each chart remembers its settings, including across a test-host relaunch.
        let suite = "PowerJackDataTabTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let screen = try await HostedView(
            PowerJackRootView()
                .defaultAppStorage(defaults)
                .modelContainer(container)
                .environment(PowerJackStore(inMemory: true))
        )
        defer { screen.close() }

        await screen.selectTab("Data")
        let left = TrainingStudy.legWork.genericName
        let right = TrainingStudy.armReps.genericName
        try #require(await screen.waitUntil { screen.contains(left) && screen.contains(right) })
        let first = try #require(screen.frame(of: left))
        let second = try #require(screen.frame(of: right))
        #expect(first.midX < second.midX)
        #expect(abs(first.minY - second.minY) < 2)
        try #require(await screen.tap(right))
        #expect(await screen.waitUntil { screen.contains(TrainingStudy.armReps.caption) })
        #expect(await screen.waitUntil { screen.contains("No matching history") })
        #expect(screen.contains("How to Read"))
        let question = "Where did your direct reps go?"
        #expect(!screen.contains(question))
        try #require(await screen.tap("How to Read"))
        #expect(await screen.waitUntil { screen.contains(question) })
        try #require(await screen.tap("How to Read"))
        #expect(await screen.waitUntil { !screen.contains(question) })
        try #require(await screen.goBack())
        #expect(screen.contains(left))
    }

    @Test("A fresh gallery opens each card with its own saved view")
    func rememberedChartViews() async throws {
        let suite = "PowerJackSavedChartTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reps = StudyOptions(period: .year(2025), muscles: [.biceps])
        let credits = StudyOptions(period: .year(2026), muscles: [.quads])
        var data = try SavedStudyViews(data: Data()).saving(reps, for: .armReps)
        data = try SavedStudyViews(data: data).saving(credits, for: .legWork)
        defaults.set(data, forKey: SavedStudyViews.storageKey)
        let history = StudyHistory(programs: [], archive: [], logs: [], unit: .pounds)
        let repsTitle = history.result(for: .armReps, options: reps).displayTitle
        let creditsTitle = history.result(for: .legWork, options: credits).displayTitle
        func gallery() async throws -> HostedView {
            try await HostedView(ProgramDataView().defaultAppStorage(defaults).modelContainer(container))
        }

        do {
            let first = try await gallery()
            defer { first.close() }
            try #require(await first.tap(repsTitle))
            #expect(await first.waitUntil { first.contains(repsTitle) && first.contains("How to Read") })
        }
        let reset = try SavedStudyViews(data: data).saving(StudyOptions(), for: .armReps)
        defaults.set(reset, forKey: SavedStudyViews.storageKey)
        let reopened = try await gallery()
        defer { reopened.close() }
        #expect(reopened.contains(TrainingStudy.armReps.genericName))
        try #require(await reopened.tap(creditsTitle))
        #expect(await reopened.waitUntil { reopened.contains(creditsTitle) && reopened.contains("How to Read") })
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
        #expect(await screen.waitUntil { !screen.contains("Close") }, "\(screen.labels)")
    }

    @Test("The day picker changes workouts and leaves horizontal swipes to the rows")
    func templateBuilderDayPicker() async throws {
        let screen = try await HostedView(
            NavigationStack { BuilderHost() }.modelContainer(container)
        )
        defer { screen.close() }

        #expect(screen.horizontalScrollViews.isEmpty, "A sideways pager would steal the rows' swipe actions")

        await screen.tap("Add", settleFor: .milliseconds(800))
        let bench = try #require(screen.label(startingWith: "Barbell Bench Press"), "\(screen.labels)")
        await screen.tap(bench, settleFor: .milliseconds(800))
        #expect(screen.labels.contains { $0.hasPrefix("Barbell Bench Press") }, "\(screen.labels)")
        #expect(await screen.waitUntil { !screen.contains("Close") }, "\(screen.labels)")

        try #require(await screen.selectSegment("Day 2"))
        #expect(await screen.waitUntil { !screen.labels.contains { $0.hasPrefix("Barbell Bench Press") } }, "\(screen.labels)")
        #expect(screen.horizontalScrollViews.isEmpty)

        try #require(await screen.selectSegment("Day 1"))
        #expect(await screen.waitUntil { screen.labels.contains { $0.hasPrefix("Barbell Bench Press") } }, "\(screen.labels)")
    }

    @Test("Both swipes on an exercise row show Superset | Edit | Change | Trash, and a full swipe right supersets")
    func exerciseRowSwipeActions() {
        let leading = ExerciseRowAction.actions(isLogged: false, from: .leading)
        let trailing = ExerciseRowAction.actions(isLogged: false, from: .trailing)
        #expect(leading == [.superset, .edit, .change, .trash])
        // The trailing edge lists from the right, so on screen it reads the same left to right.
        #expect(Array(trailing.reversed()) == leading)
        #expect(leading.first == .superset, "A full swipe right runs the first leading action")
        #expect(trailing.first == .trash)
    }

    @Test("A logged exercise's swipes show Superset and Edit but never Change or Trash")
    func loggedExerciseRowSwipeActions() {
        #expect(ExerciseRowAction.actions(isLogged: true, from: .leading) == [.superset, .edit])
        #expect(ExerciseRowAction.actions(isLogged: true, from: .trailing) == [.edit, .superset])
    }

    @Test("Browsing exercises opens the selected exercise's details")
    func browseExercises() async throws {
        let screen = try await HostedView(
            ExerciseSelectionView(navigationTitle: "Exercises").modelContainer(container)
        )
        defer { screen.close() }

        let curl = try #require(screen.label(startingWith: "Barbell Curl"), "\(screen.labels)")
        await screen.tap(curl, settleFor: .milliseconds(800))
        #expect(screen.contains("Built-in exercises keep their name, equipment and muscles."), "\(screen.labels)")
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

    @Test("The Templates switcher shows only the chosen section's templates")
    func templateSections() async throws {
        defer { UserDefaults.standard.removeObject(forKey: TemplateType.selectionKey) }
        let screen = try await HostedView(TemplateProgramListView().modelContainer(container))
        defer { screen.close() }
        let build = TemplateCatalog.entries.first { $0.type == .hypertrophy }!.name
        let strength = TemplateCatalog.entries.first { $0.type == .strength }!.name
        let powerJack = TemplateCatalog.entries.first { $0.type == .powerJack }!.name

        #expect(screen.label(startingWith: build) != nil, "\(screen.labels)")
        #expect(screen.label(startingWith: strength) == nil, "\(screen.labels)")

        try #require(await screen.selectSegment("Strength"))
        #expect(screen.label(startingWith: strength) != nil, "\(screen.labels)")

        try #require(await screen.selectSegment("PowerJack"))
        #expect(screen.label(startingWith: powerJack) != nil, "\(screen.labels)")
    }

    @Test("A draft with no focus muscles yet shows no divider with nothing after it")
    func draftRowWithoutMuscles() async throws {
        defer { UserDefaults.standard.removeObject(forKey: TemplateType.selectionKey) }
        container.mainContext.insert(TemplateProgram(templateName: "Just Named", workoutsPerWeek: 0, templateMuscleFocus: []))
        let screen = try await HostedView(TemplateProgramListView().modelContainer(container))
        defer { screen.close() }

        let draft = try #require(screen.label(startingWith: "(Draft) Just Named"), "\(screen.labels)")
        #expect(!draft.contains("|"), "\(draft)")
        let full = try #require(screen.label(startingWith: TemplateCatalog.entries[0].name), "\(screen.labels)")
        #expect(full.contains("|"), "\(full)")
    }

    @Test("New Template has no Save button and saves as soon as the user types")
    func newTemplateAutosaves() async throws {
        let screen = try await HostedView(
            NavigationPreviewHost(modelContainer: container) { TemplateProgramNew() }
        )
        defer { screen.close() }
        #expect(!screen.contains("Save"), "\(screen.labels)")

        #expect(await screen.typeIntoFirstField("Legs"))
        await screen.settle()
        let saved = try container.mainContext.fetch(FetchDescriptor<TemplateProgram>(
            predicate: #Predicate { $0.templateName == "Legs" }
        ))
        #expect(saved.count == 1)
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
