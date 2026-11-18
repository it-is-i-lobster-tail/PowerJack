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
        // The rating given before the extra set no longer covers all the work, so it's asked again.
        #expect(exercise.needsFeedback)
        #expect(!exercise.isDone)
    }

    @Test("Sets added and logged after rating ask again, and the new answer replaces the old one")
    func feedbackAskedAgainAfterMoreSets() throws {
        let workout = try makeStartedWorkout(exercises: 1)
        let exercise = workout.workoutExercises[0]
        let context = container.mainContext
        logWorkingSets(of: exercise)
        let logged = exercise.completedWorkingSets
        #expect(exercise.needsFeedback)
        #expect(exercise.answerFeedback(ExerciseFeedback(levelOfEffort: .easy, levelOfPain: .none), topSet: nil))
        #expect(exercise.feedback?.completedSets == logged)

        // Two more sets, then the last one is removed again, and only the one left is logged.
        _ = try #require(exercise.addSet())
        _ = try #require(exercise.addSet())
        exercise.removeLastSet()
        #expect(exercise.workingSets.count == logged + 1)
        #expect(!exercise.needsFeedback)
        let extra = try #require(exercise.workingSets.last)
        extra.reps = 8
        extra.weightTenthsPounds = 1000
        exercise.completeSet(extra)

        #expect(exercise.needsFeedback)
        #expect(!exercise.isDone)
        #expect(workout.currentExerciseIndex == 0)
        #expect(exercise.answerFeedback(ExerciseFeedback(levelOfEffort: .veryHard, levelOfPain: .mild), topSet: nil))
        #expect(exercise.feedback?.levelOfEffort == .veryHard)
        #expect(exercise.feedback?.completedSets == logged + 1)
        #expect(!exercise.needsFeedback)
        #expect(exercise.isDone)
        try context.save()
        // The first answer's row is gone, not left behind.
        #expect(try context.fetchCount(FetchDescriptor<ExerciseFeedback>()) == 1)
    }

    @Test("Logging one of two added sets, then removing the other, asks again")
    func feedbackAskedAgainWhenUnloggedSetRemoved() throws {
        let workout = try makeStartedWorkout(exercises: 1)
        let exercise = workout.workoutExercises[0]
        logWorkingSets(of: exercise)
        exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))

        let logged = try #require(exercise.addSet())
        _ = try #require(exercise.addSet())
        logged.reps = 8
        logged.weightTenthsPounds = 1000
        exercise.completeSet(logged)
        // The second added set is still open, so the lifter isn't done yet.
        #expect(!exercise.needsFeedback)

        exercise.removeLastSet()

        #expect(exercise.allSetsDone())
        #expect(exercise.needsFeedback)
        #expect(!exercise.isDone)
    }

    @Test("A set added after rating but skipped, not logged, doesn't ask again")
    func addedSetSkippedKeepsFeedback() throws {
        let workout = try makeStartedWorkout(exercises: 1)
        let exercise = workout.workoutExercises[0]
        logWorkingSets(of: exercise)
        exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))

        _ = try #require(exercise.addSet())
        exercise.skipRemainingSets()

        #expect(!exercise.needsFeedback)
        #expect(exercise.isDone)
    }

    @Test("Unchecking and logging a set again after rating doesn't ask again")
    func relogKeepsFeedback() throws {
        let workout = try makeStartedWorkout(exercises: 1)
        let exercise = workout.workoutExercises[0]
        logWorkingSets(of: exercise)
        exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
        let last = try #require(exercise.workingSets.last)

        last.start()
        #expect(!exercise.isDone)
        last.complete()

        #expect(!exercise.needsFeedback)
        #expect(exercise.isDone)
    }

    @Test("A rating saved before the set count was kept isn't asked again")
    func olderFeedbackStands() throws {
        let workout = try makeStartedWorkout(exercises: 1)
        let exercise = workout.workoutExercises[0]
        logWorkingSets(of: exercise)
        exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
        let feedback = try #require(exercise.feedback)
        var older = feedback.syncState
        older.completedSets = nil
        feedback.apply(older)

        let extra = try #require(exercise.addSet())
        extra.reps = 8
        extra.weightTenthsPounds = 1000
        extra.complete()

        #expect(!exercise.needsFeedback)
        #expect(exercise.isDone)
    }

    @Test("Skip Exercise leaves the exercise open, and adding a set brings it back")
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

    @Test("Restore Exercise brings back the skipped sets and keeps the logged ones")
    func restoreSkippedExercise() throws {
        let workout = try makeStartedWorkout(exercises: 1)
        let exercise = workout.workoutExercises[0]
        let first = try #require(exercise.workingSets.first)
        first.reps = 10
        first.weightTenthsPounds = 1000
        exercise.completeSet(first)
        let rest = exercise.workingSets.dropFirst()
        #expect(!rest.isEmpty)

        exercise.skipRemainingSets()
        #expect(exercise.canRestoreSkipped)
        exercise.restoreSkipped()

        #expect(exercise.status == .active)
        #expect(!exercise.locked)
        #expect(!exercise.canRestoreSkipped)
        #expect(!exercise.isDone)
        #expect(!exercise.needsFeedback)
        #expect(first.status == .complete && first.reps == 10 && first.weightTenthsPounds == 1000)
        #expect(rest.allSatisfy { $0.status == .active && !$0.locked })
        // A logged working set had already passed over the warmups.
        #expect(exercise.warmupSets.allSatisfy { $0.status == .skipped })
    }

    @Test("Restoring an exercise skipped before any set brings its warmups back too")
    func restoreUntouchedExercise() throws {
        let workout = try makeStartedWorkout(exercises: 1)
        let exercise = workout.workoutExercises[0]

        exercise.skipRemainingSets()
        exercise.restoreSkipped()

        #expect(exercise.status == .active)
        #expect(exercise.workoutSets.allSatisfy { $0.status == .active })
    }

    @Test("A skipped exercise can't be restored once its workout is finished")
    func finishedExerciseCantRestore() throws {
        let program = try makeStartedProgram(exercises: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = workout.workoutExercises[0]
        exercise.skipRemainingSets()
        program.finishWorkout(workout)

        #expect(exercise.locked)
        #expect(!exercise.canRestoreSkipped)
        exercise.restoreSkipped()
        #expect(exercise.status == .skipped)
        #expect(exercise.workingSets.allSatisfy { $0.status == .skipped })
    }

    @Test("The workout menu offers Restore Exercise once the exercise is skipped")
    func restoreLabelReplacesSkip() async throws {
        let program = try makeStartedProgram(exercises: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        workout.workoutExercises[0].skipRemainingSets()
        try container.mainContext.save()

        let screen = try await HostedView(session(program))
        defer { screen.close() }

        // The workout opens on the first unfinished exercise, so go back to the skipped one.
        await screen.tap("Bench", settleFor: .milliseconds(800))
        #expect(await screen.tap("More", settleFor: .milliseconds(800)), "\(screen.labels)")
        let labels = screen.labelsInAllWindows
        #expect(labels.contains("Restore Exercise"), "\(labels)")
        #expect(!labels.contains("Skip Exercise"), "\(labels)")
    }

    @Test("Every workout menu hint is short enough to show in full")
    func menuHintsFit() {
        for hint in WorkoutActionsMenu.Hint.all {
            #expect(!hint.isEmpty)
            #expect(hint.count <= WorkoutActionsMenu.Hint.maxLength, "\(hint)")
        }
    }

    @Test("The workout menu names what each skip covers")
    func skipLabelsNameTheirScope() async throws {
        let program = try makeStartedProgram(exercises: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        try container.mainContext.save()

        let screen = try await HostedView(session(program))
        defer { screen.close() }

        #expect(await screen.tap("More", settleFor: .milliseconds(800)), "\(screen.labels)")
        let labels = screen.labelsInAllWindows
        #expect(labels.contains("Skip Exercise"), "\(labels)")
        #expect(labels.contains("Skip Workout"), "\(labels)")
        #expect(!labels.contains("Skip Remaining Sets"), "\(labels)")
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
        #expect(screen.labels.contains { $0.hasPrefix("Workout timer") }, "\(screen.labels)")
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
