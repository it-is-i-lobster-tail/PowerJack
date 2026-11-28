//
//  EquipmentDetailTests.swift
//  PowerJackTests
//
//  Equipment opens its load step, and the lifter's own equipment can be deleted or replaced.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct EquipmentDetailTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() {
        container = PowerJackSeed.makeInMemoryContainer()
    }

    /// Runs `body` with the unit and a barbell step saved, then puts back whatever was there.
    private func withSaved(unit: WeightUnit, barbellStep: Double, _ body: () async throws -> Void) async rethrows {
        let defaults = UserDefaults.standard
        let keys = [AppSettings.Key.weightUnit, StrengthLoadSteps.key(for: .barbell, in: unit)]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        defaults.set(unit.rawValue, forKey: keys[0])
        defaults.set(barbellStep, forKey: keys[1])
        try await body()
    }

    @Test("A load step saved before this screen reads back unchanged, and editing it saves to the same place")
    func savedLoadStepCarriesOver() async throws {
        try await withSaved(unit: .pounds, barbellStep: 2.5) {
            let key = StrengthLoadSteps.key(for: .barbell, in: .pounds)
            // The key the old Load Steps screen saved to. Changing it would drop every lifter's saved steps.
            #expect(key == "settings.strength.loadStep.lb.barbell")

            let screen = try await HostedView(NavigationStack { MyGymSettingsView() }.modelContainer(container))
            #expect(screen.label(startingWith: "Load Steps") == nil, "\(screen.labels)")

            let equipment = try #require(screen.label(startingWith: "Equipment"), "\(screen.labels)")
            #expect(await screen.tap(equipment, settleFor: .milliseconds(600)))
            #expect(await screen.tap("Barbell", settleFor: .milliseconds(600)), "\(screen.labels)")

            // Shows the saved 2.5 lb, not the 5 lb default, and opening the screen changes nothing.
            let picker = try #require(screen.label(startingWith: "Load Step"), "\(screen.labels)")
            #expect(picker.contains("2.5 lb") || screen.value(of: picker) == "2.5 lb", "\(screen.labels)")
            #expect(UserDefaults.standard.double(forKey: key) == 2.5)
            #expect(StrengthLoadSteps.step(for: .barbell, in: .pounds) == 2.5)
            screen.close()

            // The screen's picker is a menu, which can't be driven here, so pick from the same control inline.
            let inline = try await HostedView(Form { LoadStepPicker(equipment: .barbell, unit: .pounds) }.pickerStyle(.inline))
            defer { inline.close() }
            #expect(await inline.tap("10 lb", settleFor: .milliseconds(600)), "\(inline.labels)")
            #expect(UserDefaults.standard.double(forKey: key) == 10)
            #expect(StrengthLoadSteps.step(for: .barbell, in: .pounds) == 10)
        }
    }

    @Test("Bodyweight has no load step, so it doesn't open")
    func bodyweightDoesNotOpen() async throws {
        let screen = try await HostedView(NavigationStack { EquipmentList() }.modelContainer(container))
        defer { screen.close() }
        #expect(screen.contains("Bodyweight"))
        await screen.tap("Bodyweight", settleFor: .milliseconds(600))
        #expect(screen.label(startingWith: "Load Step") == nil, "\(screen.labels)")
    }

    @Test("Unused equipment deletes after one confirmation")
    func deleteUnused() async throws {
        context.insert(CustomEquipment(name: "EX Bar", base: .barbell))
        try context.save()

        let screen = try await HostedView(NavigationStack { EquipmentList() }.modelContainer(container))
        defer { screen.close() }
        #expect(await screen.tap("EX Bar", settleFor: .milliseconds(600)), "\(screen.labels)")
        #expect(screen.contains("Type, Barbell"), "\(screen.labels)")
        #expect(await screen.tap("Delete Equipment", settleFor: .milliseconds(600)))
        #expect(try context.fetchCount(FetchDescriptor<CustomEquipment>()) == 1, "Deleted before confirming")
        #expect(await screen.tap("Delete", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(try context.fetchCount(FetchDescriptor<CustomEquipment>()) == 0)
        // Back on the list once it's gone.
        #expect(await screen.waitUntil { screen.contains("Create equipment") && !screen.contains("Delete Equipment") }, "\(screen.labels)")
    }

    @Test("Used equipment won't delete without a replacement")
    func usedNeedsReplacement() throws {
        let equipment = CustomEquipment(name: "EX Bar", base: .barbell)
        context.insert(equipment)
        context.insert(ownExercise("EX Curl", on: equipment))
        try context.save()

        try equipment.delete(movingExercisesTo: nil, in: context)
        #expect(try context.fetchCount(FetchDescriptor<CustomEquipment>()) == 1)
    }

    @Test("Replacing moves every exercise that used it, keeps their logged sets, and leaves built-in exercises alone")
    func replaceKeepsHistory() async throws {
        let equipment = CustomEquipment(name: "EZ Bar", base: .barbell)
        let other = CustomEquipment(name: "Dip Belt", base: .loadableBodyweight)
        context.insert(equipment)
        context.insert(other)
        let curl = ownExercise("EZ Curl", on: equipment)
        let skull = ownExercise("Skull Crusher", on: equipment)
        // A built-in exercise can name equipment like the lifter's own.
        let builtIn = Exercise(exerciseName: "EZ Bar Curl", exerciseEquipment: .barbell, primaryMuscleFocus: .biceps)
        builtIn.customEquipmentName = "EZ Bar"
        for exercise in [curl, skull, builtIn] { context.insert(exercise) }

        let template = TemplateProgram(templateName: "Arms", workoutsPerWeek: 1, templateMuscleFocus: [.biceps])
        template.addTemplateWorkout().addTemplateExercise(exercise: curl)
        context.insert(template)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        context.insert(program)
        try context.save()
        let row = try #require(program.programWeeks.first?.workouts.first?.workoutExercises.first)
        let setCount = row.workoutSets.count
        #expect(setCount > 0)
        #expect(try equipment.exercises(in: context).count == 2)

        try equipment.delete(movingExercisesTo: other.base, named: other.name, in: context)

        #expect(try context.fetch(FetchDescriptor<CustomEquipment>()).map(\.name) == ["Dip Belt"])
        for exercise in [curl, skull] {
            #expect(exercise.customEquipmentName == "Dip Belt")
            #expect(exercise.equipment == .loadableBodyweight)
            #expect(exercise.equipmentDisplayName == "Dip Belt")
        }
        #expect(builtIn.customEquipmentName == "EZ Bar")
        #expect(builtIn.equipment == .barbell)
        #expect(row.exercise === curl)
        #expect(row.workoutSets.count == setCount)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 3)
    }

    @Test("Replacing with built-in equipment clears the custom name")
    func replaceWithBuiltIn() throws {
        let equipment = CustomEquipment(name: "EX Bar", base: .barbell)
        context.insert(equipment)
        let exercise = ownExercise("EX Curl", on: equipment)
        context.insert(exercise)
        try context.save()

        try equipment.delete(movingExercisesTo: .dumbbell, in: context)
        #expect(exercise.customEquipmentName == nil)
        #expect(exercise.equipment == .dumbbell)
    }

    private func ownExercise(_ name: String, on equipment: CustomEquipment) -> Exercise {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: equipment.base, primaryMuscleFocus: .biceps, userCreated: true)
        exercise.customEquipmentName = equipment.name
        return exercise
    }
}
