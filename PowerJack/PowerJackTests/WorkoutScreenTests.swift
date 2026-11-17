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
    private let container = HostedView.makeStore()
    private let router = ProgramsRouter()

    @Test("Logging every set asks for feedback, then Review, then the summary and back to the program")
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
        await screen.tap("Set 1")
        #expect(sets[0].status == .complete)

        // Unchecking reopens the set, and Undo puts it back as it was.
        let completedAt = sets[0].completedAt
        await screen.tap("Set 1")
        #expect(sets[0].status == .active)
        #expect(screen.contains("Undo"), "\(screen.labels)")
        await screen.tap("Undo")
        #expect(sets[0].status == .complete)
        #expect(sets[0].completedAt == completedAt)

        await screen.type("abc12", into: "Set 2 reps")
        await screen.type("9", into: "Set 2 reps")
        await screen.tap("Set 2", settleFor: .milliseconds(800))
        #expect(sets.allSatisfy { $0.status == .complete })

        // Feedback opens once every set is logged, titled with the exercise's name.
        #expect(screen.contains("Level of Pain"), "\(screen.labels)")
        #expect(screen.contains("Bench"), "\(screen.labels)")
        await screen.tap(scaleLabel(RepsInReserve.two))
        await screen.tap(scaleLabel(LevelOfPain.mild), settleFor: Feedback.undoWindow + .milliseconds(800))

        // Rating the last exercise opens Review once its Undo window passes; only Finish Workout
        // ends the workout.
        #expect(exercise.feedback != nil)
        #expect(workout.status == .active)
        #expect(!exercise.locked)
        #expect(screen.contains("Finish Workout"), "\(screen.labels)")
        await screen.tap("Finish Workout", settleFor: .milliseconds(800))
        #expect(workout.status == .complete)
        #expect(exercise.locked)

        #expect(screen.contains("Workout complete!"), "\(screen.labels)")
        await screen.tap("Done", settleFor: .milliseconds(800))
        #expect(router.path == [.detail(program)])
        let next = try #require(program.nextWorkout)
        #expect(next !== workout)
        #expect(next.status == .planned)
        #expect(program.weekNumber(containing: next) == 2)
    }

    @Test("Feedback waits a moment with Undo before it's saved, and the current set says it's not done")
    func feedbackUndo() async throws {
        let program = try makeStartedProgram(weeks: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let screen = try await HostedView(session(program))
        defer { screen.close() }
        let exercise = try #require(workout.workoutExercises.first)
        exercise.warmupSets.forEach { $0.complete() }
        for number in 1...2 {
            #expect(await screen.type("100", into: "Set \(number) weight"))
            #expect(await screen.type("10", into: "Set \(number) reps"))
        }
        #expect(screen.value(of: "Set 1") == "Not done")
        await screen.tap("Set 1")
        #expect(screen.value(of: "Set 1") == "Done")
        await screen.tap("Set 2", settleFor: .milliseconds(800))

        await screen.tap(scaleLabel(RepsInReserve.two))
        await screen.tap(scaleLabel(LevelOfPain.mild))
        #expect(screen.contains("Undo"), "\(screen.labels)")
        #expect(exercise.feedback == nil)

        await screen.tap("Undo")
        #expect(screen.contains("Level of Pain"), "\(screen.labels)")
        await screen.tap(scaleLabel(LevelOfPain.mild), settleFor: Feedback.undoWindow + .milliseconds(800))
        #expect(exercise.feedback != nil)
    }

    @Test("Finishing with an exercise only partly logged asks its feedback first, then finishes")
    func finishAsksFeedbackFirst() async throws {
        let program = try makeStartedProgram(weeks: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let screen = try await HostedView(session(program))
        defer { screen.close() }
        let exercise = try #require(workout.workoutExercises.first)
        exercise.warmupSets.forEach { $0.complete() }
        #expect(await screen.type("100", into: "Set 1 weight"))
        #expect(await screen.type("10", into: "Set 1 reps"))
        await screen.tap("Set 1")

        // Over to Review with set 2 still to do, and finish.
        await screen.tap("Review", settleFor: .milliseconds(800))
        await screen.tap("Finish Workout", settleFor: .milliseconds(800))
        await screen.tap("Skip and Finish", settleFor: .milliseconds(800))
        #expect(screen.contains("Level of Pain"), "\(screen.labels)")
        #expect(workout.status == .active)

        // The answers are saved once the Undo window passes, and then the workout finishes.
        await screen.tap(scaleLabel(RepsInReserve.two))
        await screen.tap(scaleLabel(LevelOfPain.mild), settleFor: Feedback.undoWindow + .milliseconds(1200))
        #expect(exercise.feedback != nil)
        #expect(workout.status == .complete)
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
        #expect(!hasLabel(containing: "Warmup done", in: screen))

        exercise.skipWarmups()
        await screen.settle(.milliseconds(1200))
        #expect(!screen.contains("Warmup 1 weight"), "\(screen.labels)")
        #expect(hasLabel(containing: "Warmup done", in: screen), "\(screen.labels)")
        #expect(screen.contains("Set 1 weight"))

        // Tapping WARMUP shows the finished warmups again, and tapping it again hides them.
        let title = try #require(screen.labels.first { $0.hasPrefix("Warmup") && $0.contains("done") }, "\(screen.labels)")
        await screen.tap(title, settleFor: .milliseconds(800))
        #expect(screen.contains("Warmup 1 weight"), "\(screen.labels)")
        await screen.tap(title, settleFor: .milliseconds(800))
        #expect(!screen.contains("Warmup 1 weight"), "\(screen.labels)")

        exercise.disableWarmups()
        await screen.settle()
        #expect(!screen.contains("Warmup options"), "\(screen.labels)")
        #expect(!hasLabel(containing: "Warmup done", in: screen))

        // Working sets get the same check once they're all done.
        #expect(!hasLabel(containing: "Working Sets done", in: screen))
        for set in exercise.workingSets {
            set.reps = 8
            set.weightTenthsPounds = 1000
            set.complete()
        }
        await screen.settle(.milliseconds(800))
        #expect(hasLabel(containing: "Working Sets done", in: screen), "\(screen.labels)")
    }

    private func hasLabel(containing text: String, in screen: HostedView) -> Bool {
        screen.labels.contains { $0.contains(text) }
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
