//
//  WorkoutReviewTests.swift
//  PowerJackTests
//
//  Exercises stay open until Finish Workout, so the lifter can go back for one more set.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct WorkoutReviewTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let router = ProgramsRouter()

    @Test("Rating an exercise keeps it open for one more set")
    func feedbackKeepsExerciseOpen() throws {
        let workout = try makeStartedWorkout(exercises: 1)
        let exercise = workout.workoutExercises[0]
        logWorkingSets(of: exercise)
        exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))

        #expect(exercise.isDone)
        #expect(!exercise.locked)
        #expect(workout.allExercisesFinished)

        let extra = try #require(exercise.addSet())
        #expect(!exercise.isDone)
        #expect(!workout.allExercisesFinished)
        #expect(workout.currentExerciseIndex == 0)

        extra.reps = 8
        extra.weightTenthsPounds = 1000
        extra.complete()
        // The rating already given still counts, so it isn't asked for again.
        #expect(!exercise.needsFeedback)
        #expect(exercise.isDone)
    }

    @Test("Skip Remaining Sets leaves the exercise open, and adding a set brings it back")
    func skipRemainingSetsStaysOpen() throws {
        let workout = try makeStartedWorkout(exercises: 1)
        let exercise = workout.workoutExercises[0]
        let first = try #require(exercise.workingSets.first)
        first.reps = 10
        first.weightTenthsPounds = 1000
        first.complete()

        exercise.skipRemainingSets()
        #expect(exercise.status == .skipped)
        #expect(!exercise.locked)
        #expect(exercise.workingSets.last?.status == .skipped)
        #expect(first.status == .complete)
        #expect(exercise.needsFeedback)

        _ = try #require(exercise.addSet())
        #expect(exercise.status == .active)
        #expect(!exercise.isDone)
    }

    @Test("Finishing skips unlogged sets and locks every exercise")
    func finishSkipsAndLocks() throws {
        let program = try makeStartedProgram(exercises: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let (done, untouched) = (workout.workoutExercises[0], workout.workoutExercises[1])
        logWorkingSets(of: done)
        done.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
        #expect(workout.remainingWorkingSets == untouched.workingSets.count)

        workout.skipRemainingSets()
        program.finishWorkout(workout)

        #expect(workout.status == .complete)
        #expect(done.locked && untouched.locked)
        #expect(done.workingSets.allSatisfy { $0.status == .complete })
        // Never marked complete without being logged.
        #expect(untouched.workingSets.allSatisfy { $0.status == .skipped })
    }

    @Test("Review lists the exercises and asks before finishing with unlogged sets")
    func reviewAsksBeforeSkipping() async throws {
        let program = try makeStartedProgram(exercises: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let (done, untouched) = (workout.workoutExercises[0], workout.workoutExercises[1])
        logWorkingSets(of: done)
        done.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
        try container.mainContext.save()

        let screen = try await HostedView(session(program))
        defer { screen.close() }

        await screen.tap("Review", settleFor: .milliseconds(800))
        #expect(screen.contains("Finish Workout"), "\(screen.labels)")
        #expect(screen.labels.contains { $0.hasPrefix("Bench") && $0.contains("Done") }, "\(screen.labels)")
        #expect(screen.labels.contains { $0.hasPrefix("Row") && $0.contains("Not done") }, "\(screen.labels)")

        // Unlogged sets ask first instead of finishing; Finish with nothing left is covered in WorkoutScreenTests.
        await screen.tap("Finish Workout")
        #expect(await screen.waitUntil { screen.contains("Skip and Finish") }, "\(screen.labels)")
        #expect(workout.status == .active)
        #expect(untouched.workingSets.allSatisfy { $0.status == .active })
    }

    // MARK: Helpers

    private func session(_ program: Program) -> some View {
        ReviewSessionHost(router: router, program: program)
            .modelContainer(container)
    }

    private func logWorkingSets(of exercise: WorkoutExercise) {
        for set in exercise.workingSets {
            set.reps = 10
            set.weightTenthsPounds = 1000
            set.complete()
        }
    }

    private func makeStartedWorkout(exercises: Int) throws -> Workout {
        let program = try makeStartedProgram(exercises: exercises)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        return workout
    }

    private func makeStartedProgram(exercises count: Int) throws -> Program {
        let context = container.mainContext
        let exercises = [("Bench", Muscle.chest), ("Row", Muscle.back)].prefix(count).map { name, muscle in
            Exercise(
                exerciseName: name,
                exerciseEquipment: .barbell,
                primaryMuscleFocus: muscle,
                minReps: 6,
                maxReps: 12
            )
        }
        exercises.forEach(context.insert)
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        let templateWorkout = template.addTemplateWorkout()
        for exercise in exercises { _ = templateWorkout.addTemplateExercise(exercise: exercise) }
        context.insert(template)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        try context.save()
        return program
    }
}

private struct ReviewSessionHost: View {
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
