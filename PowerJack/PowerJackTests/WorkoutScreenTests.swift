//
//  WorkoutScreenTests.swift
//  PowerJackTests
//
//  Drives the workout screens the way a lifter does: log sets, rate the exercise, move on.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct WorkoutScreenTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let router = ProgramsRouter()

    @Test("Logging every set asks for feedback, then shows the summary and returns to the program")
    func logWorkoutThroughSummary() async throws {
        let program = try makeStartedProgram(weeks: 2)
        let workout = try #require(program.nextWorkout)
        // Nothing starts on its own: this is the Start Workout tap.
        #expect(workout.status == .planned)
        workout.startAndCascade()
        let screen = try await HostedView(session(program))
        defer { screen.close() }
        let exercise = try #require(workout.workoutExercises.first)
        let sets = exercise.workingSets

        // Warmups are numbered on their own, so "Set 1" is the first working set.
        #expect(await screen.type("45", into: "Warmup 1 weight"), "\(screen.labels)")
        #expect(exercise.warmupSets.map(\.weightTenthsPounds) == [450, 450])
        #expect(sets[0].weightTenthsPounds == nil)
        exercise.warmupSets.forEach { $0.complete() }

        #expect(await screen.type("100", into: "Set 1 weight"), "\(screen.labels)")
        #expect(await screen.type("10", into: "Set 1 reps"))
        #expect(sets[1].weightTenthsPounds == 1000)
        await screen.tap("Set 1 complete")
        #expect(sets[0].status == .complete)

        // Unchecking reopens the set; checking it again completes it.
        await screen.tap("Set 1 complete")
        #expect(sets[0].status == .active)
        await screen.tap("Set 1 complete")

        await screen.type("abc12", into: "Set 2 reps")
        await screen.type("9", into: "Set 2 reps")
        await screen.tap("Set 2 complete", settleFor: .milliseconds(800))
        #expect(sets.allSatisfy { $0.status == .complete })

        // Feedback opens once every set is logged.
        #expect(screen.contains("Exercise Feedback"), "\(screen.labels)")
        await screen.tap(scaleLabel(LevelOfEffort.challenge))
        await screen.tap(scaleLabel(LevelOfPain.mild), settleFor: .milliseconds(800))
        #expect(workout.status == .complete)

        #expect(screen.contains("Workout complete!"), "\(screen.labels)")
        await screen.tap("Done", settleFor: .milliseconds(800))
        #expect(router.path == [.detail(program)])
        let next = try #require(program.nextWorkout)
        #expect(next !== workout)
        #expect(next.status == .planned)
        #expect(program.weekNumber(containing: next) == 2)
    }

    @Test("Finished warmups fold away and check off their heading; disabled ones disappear")
    func warmupsCollapse() async throws {
        let program = try makeStartedProgram(weeks: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let screen = try await HostedView(session(program))
        defer { screen.close() }
        let exercise = try #require(workout.workoutExercises.first)

        #expect(screen.contains("Warmup 1 weight"), "\(screen.labels)")
        #expect(!screen.contains("Warmup done"))

        exercise.skipWarmups()
        await screen.settle(.milliseconds(1200))
        #expect(!screen.contains("Warmup 1 weight"), "\(screen.labels)")
        #expect(screen.contains("Warmup done"), "\(screen.labels)")
        #expect(screen.contains("Set 1 weight"))

        exercise.disableWarmups()
        await screen.settle()
        #expect(!screen.contains("Warmup options"), "\(screen.labels)")
        #expect(!screen.contains("Warmup done"))
    }

    @Test("A severe-pain exercise opens the check-in, and continue keeps the held sets")
    func checkInSheet() async throws {
        let program = try makeStartedProgram(weeks: 2)
        let first = try #require(program.nextWorkout)
        first.startAndCascade()
        log(first, pain: .severe)
        let next = try #require(program.finishWorkout(first))
        next.startAndCascade()
        try container.mainContext.save()

        let screen = try await HostedView(session(program))
        defer { screen.close() }

        let exercise = try #require(next.workoutExercises.first)
        #expect(screen.contains("Check In"), "\(screen.labels)")
        let decision = try #require(screen.labels.first { $0.hasPrefix("Continue") }, "\(screen.labels)")
        await screen.tap(decision)
        #expect(exercise.checkIn == .resolved)
        #expect(exercise.status == .active)
    }

    @Test("Skipping a held exercise at check-in moves past it")
    func checkInSkip() async throws {
        let program = try makeStartedProgram(weeks: 2)
        let first = try #require(program.nextWorkout)
        first.startAndCascade()
        log(first, pain: .extreme)
        let next = try #require(program.finishWorkout(first))
        next.startAndCascade()
        try container.mainContext.save()

        let screen = try await HostedView(session(program))
        defer { screen.close() }

        let decision = try #require(screen.labels.first { $0.hasPrefix("Skip") }, "\(screen.labels)")
        await screen.tap(decision, settleFor: .milliseconds(800))
        #expect(next.workoutExercises.first?.status == .skipped)
    }

    @Test("A finished program shows that it is complete")
    func programComplete() async throws {
        let program = try makeStartedProgram(weeks: 1)
        let workout = try #require(program.nextWorkout)
        program.skipWorkout(workout)
        #expect(program.status == .complete)

        let screen = try await HostedView(session(program))
        defer { screen.close() }
        #expect(screen.contains("Program complete"), "\(screen.labels)")
    }

    // MARK: Helpers

    private func session(_ program: Program) -> some View {
        SessionHost(router: router, program: program)
            .modelContainer(container)
    }

    private func scaleLabel<Option: ScaleSelectorOption>(_ option: Option) -> String {
        "\(option.rawValue), \(option.label)"
    }

    private func makeStartedProgram(weeks: Int) throws -> Program {
        let context = container.mainContext
        let exercise = Exercise(
            exerciseName: "Bench",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 12
        )
        context.insert(exercise)
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        context.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        try context.save()
        return program
    }

    private func log(_ workout: Workout, pain: LevelOfPain) {
        for exercise in workout.workoutExercises {
            for set in exercise.workoutSets {
                set.reps = 10
                set.weightTenthsPounds = 1000
                set.complete()
            }
            exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: pain))
            exercise.completeAndCascade()
        }
    }
}

private struct SessionHost: View {
    @Bindable var router: ProgramsRouter
    let program: Program

    var body: some View {
        NavigationStack(path: $router.path) {
            ProgramSessionView(program: program)
                .programRouteDestinations()
        }
        .environment(router)
    }
}
