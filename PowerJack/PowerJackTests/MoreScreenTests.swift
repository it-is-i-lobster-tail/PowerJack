//
//  MoreScreenTests.swift
//  PowerJackTests
//
//  Editing forms, the program detail screen and the Live Activity's check button.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct MoreScreenTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("Editing a custom exercise saves the new name")
    func editCustomExercise() async throws {
        let exercise = Exercise(exerciseName: "Cable Fly", exerciseEquipment: .cable, primaryMuscleFocus: .chest, userCreated: true)
        container.mainContext.insert(exercise)
        let saved = SavedExercise()
        let screen = try await HostedView(
            NavigationStack {
                ExerciseDetailView(exercise: exercise, onSave: { saved.exercise = $0 })
            }
            .modelContainer(container)
        )
        defer { screen.close() }

        #expect(await screen.typeIntoFirstField("Low Cable Fly"), "\(screen.labels)")
        await screen.dismissKeyboard()
        #expect(await screen.tap("Save", settleFor: .milliseconds(600)), "\(screen.labels)")
        #expect(exercise.exerciseName == "Low Cable Fly")
        #expect(saved.exercise === exercise)
    }

    @Test("Renaming a template saves it as you type")
    func templateAutosave() async throws {
        let exercise = Exercise(exerciseName: "Bench", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        container.mainContext.insert(exercise)
        let template = TemplateProgram(templateName: "Push", workoutsPerWeek: 2, templateMuscleFocus: [.chest])
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        container.mainContext.insert(template)
        try container.mainContext.save()

        let screen = try await HostedView(
            NavigationStack { TemplateProgramDetailView(templateProgram: template) }
                .modelContainer(container)
        )
        defer { screen.close() }

        #expect(await screen.typeIntoFirstField("Push Day"), "\(screen.labels)")
        #expect(template.templateName == "Push Day")

        // An invalid name isn't saved.
        await screen.typeIntoFirstField(" ")
        #expect(template.templateName == "Push Day")
    }

    @Test("Program detail starts the next workout and opens the session")
    func programDetailStartsWorkout() async throws {
        let program = try makeProgram()
        program.start()
        let workout = try #require(program.nextWorkout)
        let router = ProgramsRouter()

        let screen = try await HostedView(
            RouterHost(router: router) { ProgramDetailView(program: program) }
                .modelContainer(container)
        )
        defer { screen.close() }

        let start = try #require(screen.labels.first { $0.hasPrefix("Start") || $0.hasPrefix("Resume") }, "\(screen.labels)")
        await screen.tap(start, settleFor: .milliseconds(800))
        #expect(workout.status == .active)
        #expect(router.path == [.session(program)])
    }

    @Test("The router pushes each program screen")
    func routerPushes() throws {
        let program = try makeProgram()
        let router = ProgramsRouter()
        router.showNewProgram()
        router.showDetail(program)
        router.showSession(program)
        #expect(router.path == [.newProgram, .detail(program), .session(program)])

        router.showCurrentExercise(of: program)
        #expect(router.path == [.detail(program), .session(program)])
        #expect(router.currentExerciseRequest == 1)
        router.popToRoot()
        #expect(router.path.isEmpty)
    }

    @Test("The Live Activity's check button logs the current set at its target")
    func completeSetIntent() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: AppSettings.Key.restLiveActivity)
        defaults.set(false, forKey: AppSettings.Key.restLiveActivity)
        // The intent runs against the app's own store.
        let context = PowerJackApp.modelContainer.mainContext
        let exercise = Exercise(exerciseName: "Intent Push Up", exerciseEquipment: .bodyweight, primaryMuscleFocus: .chest)
        context.insert(exercise)
        let template = TemplateProgram(templateName: "Intent", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        context.insert(template)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        context.insert(program)
        defer {
            defaults.set(saved, forKey: AppSettings.Key.restLiveActivity)
            context.delete(program)
            context.delete(template)
            context.delete(exercise)
            try? context.save()
        }
        let others = try context.fetch(FetchDescriptor<Program>()).filter { $0 !== program && $0.status == .active }
        try #require(others.isEmpty)

        // Nothing active yet: the button does nothing.
        _ = try await CompleteSetIntent(exerciseOrder: 0, setOrder: 0).perform()

        program.start()
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let sets = try #require(workout.workoutExercises.first).workoutSets
        sets[0].repsPlanned = 8
        try context.save()

        _ = try await CompleteSetIntent(exerciseOrder: 0, setOrder: 0).perform()
        #expect(sets[0].status == .complete)
        #expect(sets[0].reps == 8)

        // A stale button for a set that's no longer current changes nothing.
        _ = try await CompleteSetIntent(exerciseOrder: 0, setOrder: 0).perform()
        #expect(sets[1].status == .active)
    }

    // MARK: Helpers

    private func makeProgram() throws -> Program {
        let exercise = Exercise(exerciseName: "Bench", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        container.mainContext.insert(exercise)
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        return program
    }
}

@MainActor
final class SavedExercise {
    var exercise: Exercise?
}

private struct RouterHost<Content: View>: View {
    @Bindable var router: ProgramsRouter
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack(path: $router.path) {
            content.programRouteDestinations()
        }
        .environment(router)
    }
}
