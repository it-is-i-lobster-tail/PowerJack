//
//  BuildForMeTests.swift
//  PowerJackTests
//
//  The Build for Me form: how its choices become a request, the equipment it remembers, the
//  not-enough-equipment message, and the whole flow from the Templates + menu to a saved template.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct BuildForMeTests {
    private let container: ModelContainer

    init() throws {
        container = PowerJackSeed.makeInMemoryContainer()
        try ExerciseCatalog.seed(in: container.mainContext)
        UserDefaults.standard.removeObject(forKey: TemplateType.selectionKey)
        UserDefaults.standard.removeObject(forKey: EquipmentChoice.storageKey)
    }

    // MARK: - Choices

    @Test("Every row's choice reaches the request, and turned-off equipment is left out")
    func requestMapping() {
        var choices = BuildForMeChoices(type: .strength)
        choices.workoutsPerWeek = 3
        choices.focus = [.chest, .back]
        choices.equipment.toggle(.machine)
        choices.equipment.toggle(.bench)
        choices.equipment.toggle(piece: "Trap Bar")
        choices.sessionMinutes = 75
        choices.lean = .freeWeights
        choices.supersets = true

        let request = choices.request
        #expect(request.type == .strength)
        #expect(request.workoutsPerWeek == 3)
        #expect(request.focus == [.chest, .back])
        #expect(request.equipment == TemplateRequest.allEquipment.subtracting([.machine]))
        #expect(request.setups == [.pullUpBar])
        #expect(request.missingEquipmentNames == ["Trap Bar"])
        #expect(request.sessionMinutes == 75)
        #expect(request.lean == .freeWeights)
        #expect(request.supersets)
    }

    @Test("The defaults turn everything on, so Build works right away")
    func defaultsBuild() {
        let choices = BuildForMeChoices(type: .hypertrophy)
        #expect(choices.request.equipment == TemplateRequest.allEquipment)
        #expect(choices.request.setups == TemplateRequest.allSetups)
        #expect(choices.request.missingEquipmentNames.isEmpty)
        guard case .plan(let plan) = BuildForMeOutcome(choices, exercises: BuilderExercise.catalog) else {
            Issue.record("The defaults didn't build")
            return
        }
        #expect(plan.days.count == BuildForMeChoices.defaultWorkoutsPerWeek)
    }

    @Test("Turned-off equipment is stored and read back, and lines it doesn't know are skipped")
    func rememberedEquipment() {
        var equipment = EquipmentChoice()
        equipment.toggle(.kettlebell)
        equipment.toggle(.pullUpBar)
        equipment.toggle(piece: "EZ Bar")
        #expect(EquipmentChoice(stored: equipment.stored) == equipment)
        #expect(EquipmentChoice(stored: "kind:hoverboard\nsetup:bench\nnonsense") == EquipmentChoice(stored: "setup:bench"))
        #expect(EquipmentChoice(stored: "") == EquipmentChoice())
        // Toggling twice turns it back on.
        equipment.toggle(.kettlebell)
        #expect(equipment.isOn(.kettlebell))
    }

    @Test("A chip tapped on the form is remembered for the next build")
    func formRemembersEquipment() async throws {
        let screen = try await HostedView(
            NavigationStack { BuildForMeView(type: .hypertrophy, onSave: {}) }.modelContainer(container)
        )
        defer { screen.close() }

        #expect(await screen.tap("Kettlebell"), "\(screen.labels)")
        let stored = UserDefaults.standard.string(forKey: EquipmentChoice.storageKey) ?? ""
        #expect(EquipmentChoice(stored: stored).offKinds == [.kettlebell])

        let next = try await HostedView(
            NavigationStack { BuildForMeView(type: .hypertrophy, onSave: {}) }.modelContainer(container)
        )
        defer { next.close() }
        #expect(await next.tap("Kettlebell"))
        #expect(UserDefaults.standard.string(forKey: EquipmentChoice.storageKey) == "")
    }

    // MARK: - Not enough equipment

    @Test("Too little equipment says so and names what would fix it")
    func notEnoughEquipmentMessage() throws {
        var choices = BuildForMeChoices(type: .hypertrophy)
        for kind in EquipmentItem.kinds where kind != .legPress { choices.equipment.toggle(kind) }
        guard case .notEnoughEquipment(let message) = BuildForMeOutcome(choices, exercises: BuilderExercise.catalog) else {
            Issue.record("A leg press alone built a template")
            return
        }
        #expect(message.hasPrefix("Not enough equipment to fill 3 exercises a day. Turn on "), "\(message)")
        #expect(message.contains("Barbell"), "\(message)")
        // Every kind it names does build.
        for kind in EquipmentItem.kinds where message.contains(kind.displayName) && kind != .legPress {
            var fixed = choices
            fixed.equipment.toggle(kind)
            #expect(PlanBuilder(request: fixed.request, exercises: BuilderExercise.catalog).build() != .notEnoughEquipment, "\(kind)")
        }
    }

    @Test("Strength with only bodyweight says its days need a loaded lift")
    func strengthNeedsMainLift() {
        var choices = BuildForMeChoices(type: .strength)
        for kind in EquipmentItem.kinds where kind != .bodyweight { choices.equipment.toggle(kind) }
        guard case .notEnoughEquipment(let message) = BuildForMeOutcome(choices, exercises: BuilderExercise.catalog) else {
            Issue.record("Bodyweight alone built a Strength template")
            return
        }
        #expect(message.hasPrefix("Strength days open with a loaded multi-joint lift"), "\(message)")
        #expect(message.contains("Barbell"), "\(message)")
    }

    @Test("The form shows the message inline after Build")
    func formShowsMessage() async throws {
        var equipment = EquipmentChoice()
        for kind in EquipmentItem.kinds where kind != .legPress { equipment.toggle(kind) }
        UserDefaults.standard.set(equipment.stored, forKey: EquipmentChoice.storageKey)
        let screen = try await HostedView(
            NavigationStack { BuildForMeView(type: .hypertrophy, onSave: {}) }.modelContainer(container)
        )
        defer { screen.close() }

        #expect(await screen.tap("Build"), "\(screen.labels)")
        #expect(await screen.waitUntil { screen.label(startingWith: "Not enough equipment") != nil }, "\(screen.labels)")
        #expect(!screen.contains("Save Template"))
    }

    @Test("The same choices build the same template whatever order the exercises are fetched in")
    func sameChoicesSameTemplate() throws {
        let exercises = try container.mainContext.fetch(FetchDescriptor<Exercise>())
        let choices = BuildForMeChoices(type: .hypertrophy)
        func build(_ exercises: [Exercise]) -> BuildForMeOutcome {
            BuildForMeOutcome(choices, exercises: BuildForMeView.inBuildOrder(exercises).map { BuilderExercise($0) })
        }
        #expect(build(exercises) == build(exercises.reversed()))
        #expect(build(exercises) == build(exercises.shuffled()))
    }

    @Test("With no focus asked for, the draft takes the muscles it trains most, so it can start a program")
    func draftFocusFallback() throws {
        let exercises = try container.mainContext.fetch(FetchDescriptor<Exercise>())
        let choices = BuildForMeChoices(type: .hypertrophy)
        guard case .plan(let plan) = BuildForMeOutcome(choices, exercises: exercises.map { BuilderExercise($0) }) else {
            Issue.record("No plan")
            return
        }
        let draft = plan.makeDraft(for: choices.request, exercises: exercises)
        #expect(draft.templateMuscleFocus.count == TemplateProgramDraft.maximumFocusMuscles)
        #expect(!draft.isDraft)
    }

    // MARK: - The flow

    @Test("The Templates + button offers New Template and Build for Me")
    func addMenu() async throws {
        let screen = try await HostedView(TemplateProgramListView().modelContainer(container))
        defer { screen.close() }

        #expect(await screen.tap("Add", settleFor: .milliseconds(800)), "\(screen.labels)")
        let labels = screen.labelsInAllWindows
        #expect(labels.contains("New Template") && labels.contains("Build for Me"), "\(labels)")
    }

    @Test("Build, review, then Save Template makes one template and moves the list to its type")
    func buildAndSave() async throws {
        let screen = try await HostedView(TemplateProgramListView(creation: .buildForMe).modelContainer(container))
        defer { screen.close() }
        #expect(await screen.waitUntil { screen.contains("Build") }, "\(screen.labels)")

        let type = try #require(screen.label(startingWith: "Type"), "\(screen.labels)")
        await screen.tap(type, settleFor: .milliseconds(800))
        #expect(await screen.waitUntil { screen.contains(TemplateType.powerJack.name) }, "\(screen.labels)")
        await screen.tap(TemplateType.powerJack.name, settleFor: .milliseconds(800))

        #expect(await screen.tap("Build", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(await screen.waitUntil { screen.contains("Save Template") }, "\(screen.labels)")
        // Nothing is stored while reviewing.
        #expect(try templates().isEmpty)

        await screen.tap("Save Template", settleFor: .milliseconds(800))
        let saved = try templates()
        #expect(saved.count == 1)
        #expect(saved.first?.templateType == .powerJack)
        #expect(saved.first?.draft == false)
        #expect(UserDefaults.standard.string(forKey: TemplateType.selectionKey) == TemplateType.powerJack.rawValue)
        #expect(await screen.waitUntil { screen.contains("My Templates") && !screen.contains("Save Template") }, "\(screen.labels)")
    }

    @Test("Going back from an untouched review keeps nothing and asks nothing")
    func leaveUntouched() async throws {
        let screen = try await HostedView(TemplateProgramListView(creation: .buildForMe).modelContainer(container))
        defer { screen.close() }
        #expect(await screen.waitUntil { screen.contains("Build") }, "\(screen.labels)")
        #expect(await screen.tap("Build", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(await screen.waitUntil { screen.contains("Save Template") }, "\(screen.labels)")

        #expect(await screen.goBack())
        #expect(await screen.waitUntil { screen.contains("Build") && !screen.contains("Save Template") }, "\(screen.labels)")
        #expect(!screen.contains("Discard This Template?"))
        #expect(await screen.goBack())
        #expect(await screen.waitUntil { screen.contains("My Templates") }, "\(screen.labels)")
        #expect(try templates().isEmpty)
        #expect(!container.mainContext.hasChanges)
    }

    @Test("After an edit, going back asks first, and Discard keeps nothing")
    func discardEdited() async throws {
        let screen = try await HostedView(TemplateProgramListView(creation: .buildForMe).modelContainer(container))
        defer { screen.close() }
        #expect(await screen.waitUntil { screen.contains("Build") }, "\(screen.labels)")
        #expect(await screen.tap("Build", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(await screen.waitUntil { screen.contains("Save Template") }, "\(screen.labels)")

        // Adds an exercise to day 1.
        #expect(await screen.tap("Add", settleFor: .milliseconds(800)), "\(screen.labels)")
        // The picker's rows read "Name, Equipment, |, Muscle", unlike the day's own rows.
        let squat = try #require(screen.label(startingWith: "Barbell Box Squat,"), "\(screen.labels)")
        await screen.tap(squat, settleFor: .milliseconds(800))
        #expect(await screen.waitUntil { !screen.contains("Close") }, "\(screen.labels)")

        #expect(await screen.tap("Back", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(await screen.waitUntil { screen.contains("Discard This Template?") }, "\(screen.labels)")
        await screen.tap("Discard", settleFor: .milliseconds(800))
        #expect(await screen.waitUntil { !screen.contains("Save Template") }, "\(screen.labels)")
        #expect(try templates().isEmpty)
    }

    private func templates() throws -> [TemplateProgram] {
        try container.mainContext.fetch(FetchDescriptor<TemplateProgram>())
    }
}
