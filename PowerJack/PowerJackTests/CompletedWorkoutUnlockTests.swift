//
//  CompletedWorkoutUnlockTests.swift
//  PowerJackTests
//
//  A completed workout opens read-only. Unlocking it from its ••• menu lets the lifter fix the
//  weight and reps they logged, until the app closes, and the workout stays complete.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct CompletedWorkoutUnlockTests {
    private let container = HostedView.makeStore()

    // MARK: Model

    @Test("A logged set of a completed workout takes fixed weight and reps and stays logged")
    func correctionKeepsWorkoutComplete() throws {
        let (_, workout) = try makeCompletedWorkout(weeks: 2)
        let set = try #require(workout.workoutExercises.first?.workingSets.first)
        let completedAt = set.completedAt

        #expect(set.correctWeight(454))
        #expect(set.correctReps(8))

        #expect(set.weightTenthsPounds == 454)
        #expect(set.reps == 8)
        #expect(set.status == .complete)
        #expect(set.completedAt == completedAt)
        #expect(workout.status == .complete)
        #expect(workout.locked)
    }

    @Test("Without a fix, a completed workout's sets refuse new numbers")
    func lockedSetsRefuseEdits() throws {
        let (_, workout) = try makeCompletedWorkout(weeks: 2)
        let set = try #require(workout.workoutExercises.first?.workingSets.first)

        // The plain entry path is only for sets still to do.
        set.weightTenthsPounds = 454
        set.reps = 8
        #expect(set.weightTenthsPounds == 1000)
        #expect(set.reps == 10)

        // Numbers a set can't hold are refused too.
        #expect(!set.correctReps(0))
        #expect(!set.correctReps(WorkoutSet.maxReps + 1))
        #expect(!set.correctWeight(0))
        #expect(set.reps == 10)
        #expect(set.weightTenthsPounds == 1000)
    }

    @Test("Logged and skipped sets of a finished workout can be fixed, not those of a live one")
    func correctionNeedsFinishedWorkout() throws {
        let program = try makeStartedProgram(weeks: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let set = try #require(workout.workoutExercises.first?.workingSets.first)
        log(set)

        // A live workout reopens a set to change it.
        #expect(!set.canCorrect)
        #expect(!set.correctWeight(454))
        #expect(set.weightTenthsPounds == 1000)

        // Numbers typed into a set that's then skipped.
        let skipped = try #require(workout.workoutExercises.first?.workingSets.last)
        skipped.reps = 8
        skipped.weightTenthsPounds = 900
        workout.skipRemainingSets()
        #expect(skipped.status == .skipped)
        #expect(!skipped.canCorrect)

        _ = program.finishWorkout(workout)
        #expect(set.canCorrect)
        #expect(skipped.canCorrect)
        #expect(skipped.correctWeight(950))
        #expect(skipped.correctReps(9))
        #expect(skipped.weightTenthsPounds == 950)
        #expect(skipped.reps == 9)
        #expect(skipped.status == .skipped)
    }

    @Test("A skipped warmup's fixed weight is the warmup next week plans")
    func skippedWarmupFixCarriesForward() throws {
        let program = try makeStartedProgram(weeks: 2, days: 2)
        let dayOne = try #require(program.nextWorkout)
        dayOne.startAndCascade()
        let exercise = try #require(dayOne.workoutExercises.first)
        let warmup = try #require(exercise.warmupSets.first)
        // Typed, then passed over: logging the first working set skips it.
        warmup.weightTenthsPounds = 4410
        warmup.reps = 10
        log(try #require(exercise.workingSets.first))
        #expect(warmup.status == .skipped)
        try finish(dayOne, of: program)

        #expect(warmup.correctWeight(441))
        #expect(warmup.status == .skipped)

        // Finishing the week plans the next one from what week 1 holds now.
        try finish(try #require(program.nextWorkout), of: program)
        let nextWeek = try #require(program.programWeeks.dropFirst().first)
        let planned = try #require(nextWeek.workouts.first?.workoutExercises.first?.warmupSets.first)
        #expect(planned.weightTenthsPlannedPounds == 441)
        #expect(planned.repsPlanned == 10)
    }

    @Test("A skipped set with nothing typed has nothing to fix")
    func emptySkippedSetRefusesFixes() throws {
        let (_, workout) = try makeCompletedWorkout(weeks: 2)
        let warmup = try #require(workout.workoutExercises.first?.warmupSets.first)
        #expect(warmup.status == .skipped)
        #expect(warmup.weightTenthsPounds == nil)

        #expect(!warmup.correctWeight(441))
        #expect(warmup.weightTenthsPounds == nil)
    }

    @Test("An unlock is kept in memory only, so a relaunch locks the workout again")
    func unlockIsNotSaved() throws {
        let (_, workout) = try makeCompletedWorkout(weeks: 2)
        let context = container.mainContext
        #expect(!context.hasChanges)

        let unlocks = WorkoutUnlocks()
        #expect(!unlocks.isUnlocked(workout))
        unlocks.unlock(workout)
        #expect(unlocks.isUnlocked(workout))
        #expect(!context.hasChanges)
        #expect(workout.status == .complete)

        // A fresh launch starts with nothing unlocked.
        #expect(!WorkoutUnlocks().isUnlocked(workout))

        unlocks.lock(workout)
        #expect(!unlocks.isUnlocked(workout))
    }

    @Test("Only a completed workout can be unlocked")
    func unlockNeedsCompletedWorkout() throws {
        let program = try makeStartedProgram(weeks: 2)
        let workout = try #require(program.nextWorkout)
        let unlocks = WorkoutUnlocks()

        unlocks.unlock(workout)
        #expect(!unlocks.isUnlocked(workout))
        workout.startAndCascade()
        unlocks.unlock(workout)
        #expect(!unlocks.isUnlocked(workout))
    }

    @Test("A fix after the program ended shows in its saved history")
    func correctionUpdatesSavedHistory() throws {
        let (program, workout) = try makeCompletedWorkout(weeks: 1)
        let context = container.mainContext
        #expect(program.status == .complete)
        try HistoryArchive.saveEndedPrograms(in: context)
        let exercise = try #require(workout.workoutExercises.first)
        let set = try #require(exercise.workingSets.last)

        #expect(set.correctWeight(454))
        #expect(set.correctReps(8))
        try HistoryArchive.correct(set, in: context)

        let rows = try HistoryArchive.records(in: context).map(\.row).filter { $0.setType == "Working" }
        let fixed = try #require(rows.first { $0.setNumber == exercise.number(of: set) })
        #expect(fixed.weightTenthsPounds == 454)
        #expect(fixed.reps == 8)
        // The other sets keep what they logged.
        #expect(rows.filter { $0.setNumber != fixed.setNumber }.allSatisfy { $0.weightTenthsPounds == 1000 && $0.reps == 10 })
    }

    // MARK: Screen

    @Test("A completed workout's ••• menu offers the unlock, then the lock")
    func menuOffersUnlock() async throws {
        let (_, workout) = try makeCompletedWorkout(weeks: 2)
        let screen = try await HostedView(completedWorkout(workout, unlocks: WorkoutUnlocks()))
        defer { screen.close() }

        #expect(await screen.tap("More", settleFor: .milliseconds(800)), "\(screen.labels)")
        let labels = screen.labelsInAllWindows
        // iOS 27 reads the menu row's title and subtitle together; iOS 26 reads them as two labels.
        let readsTogether = labels.contains("Unlock completed workout, Allows edits until app closes.")
        let readsApart = labels.contains("Unlock completed workout") && labels.contains("Allows edits until app closes.")
        #expect(readsTogether || readsApart, "\(labels)")
        #expect(!labels.contains("Lock workout"), "\(labels)")
        // Nothing from a live workout's menu.
        #expect(!labels.contains("Skip Workout"), "\(labels)")

        let unlocks = WorkoutUnlocks()
        unlocks.unlock(workout)
        let unlocked = try await HostedView(completedWorkout(workout, unlocks: unlocks))
        defer { unlocked.close() }
        #expect(await unlocked.tap("More", settleFor: .milliseconds(800)), "\(unlocked.labels)")
        #expect(unlocked.labelsInAllWindows.contains("Lock workout"), "\(unlocked.labelsInAllWindows)")
    }

    @Test("Once unlocked, a logged weight and reps can be fixed, and locking stops it again")
    func unlockedScreenTakesFixes() async throws {
        let (_, workout) = try makeCompletedWorkout(weeks: 2)
        let set = try #require(workout.workoutExercises.first?.workingSets.first)
        let unlocks = WorkoutUnlocks()
        let screen = try await HostedView(completedWorkout(workout, unlocks: unlocks))
        defer { screen.close() }

        // Read-only until it's unlocked.
        await screen.type("60", into: "Set 1 weight")
        await screen.dismissKeyboard()
        #expect(set.weightTenthsPounds == 1000)

        // What Unlock completed workout does.
        unlocks.unlock(workout)
        await screen.settle()
        #expect(await screen.type("45", into: "Set 1 weight"), "\(screen.labels)")
        #expect(await screen.type("12", into: "Set 1 reps"), "\(screen.labels)")
        #expect(set.weightTenthsPounds == 450)
        #expect(set.reps == 12)
        #expect(set.status == .complete)
        #expect(workout.status == .complete)
        // Saved as typed, like any set entry.
        #expect(!container.mainContext.hasChanges)

        // An emptied box can't be saved, and shows what's logged once it loses focus.
        await screen.type("", into: "Set 1 reps")
        #expect(set.reps == 12)
        await screen.dismissKeyboard()
        #expect(screen.value(of: "Set 1 reps") == "12")

        unlocks.lock(workout)
        await screen.settle()
        await screen.type("70", into: "Set 1 weight")
        #expect(set.weightTenthsPounds == 450)
    }

    @Test("Once unlocked, a skipped warmup's weight can be fixed and its check stays put")
    func unlockedScreenFixesSkippedWarmup() async throws {
        let program = try makeStartedProgram(weeks: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)
        let warmup = try #require(exercise.warmupSets.first)
        warmup.weightTenthsPounds = 4410
        warmup.reps = 10
        try finish(workout, of: program)
        #expect(warmup.status == .skipped)

        let unlocks = WorkoutUnlocks()
        unlocks.unlock(workout)
        let screen = try await HostedView(completedWorkout(workout, unlocks: unlocks))
        defer { screen.close() }

        // Done warmups are folded away; tapping their title shows them.
        let title = try #require(screen.labels.first { $0.hasPrefix("Warmup") && $0.contains("done") }, "\(screen.labels)")
        await screen.tap(title, settleFor: .milliseconds(800))
        #expect(await screen.type("44.1", into: "Warmup 1 weight"), "\(screen.labels)")
        #expect(await screen.type("8", into: "Warmup 1 reps"), "\(screen.labels)")
        #expect(warmup.weightTenthsPounds == 441)
        #expect(warmup.reps == 8)
        #expect(warmup.status == .skipped)
        #expect(!container.mainContext.hasChanges)

        // The check still can't be tapped, so the warmup stays where it was.
        await screen.tap("Warmup 1")
        #expect(warmup.status == .skipped)
    }

    // MARK: Helpers

    private func completedWorkout(_ workout: Workout, unlocks: WorkoutUnlocks) -> some View {
        NavigationStack {
            WorkoutDetailView(workout: workout, weekNumber: 1, weekCount: 2, isReadOnly: true)
        }
        .environment(\.workoutUnlocks, unlocks)
        .modelContainer(container)
    }

    private func log(_ set: WorkoutSet) {
        set.reps = 10
        set.weightTenthsPounds = 1000
        set.workoutExerciseValue?.completeSet(set)
    }

    /// Week 1's workout, every working set logged at 100 × 10 and rated, then finished.
    private func makeCompletedWorkout(weeks: Int) throws -> (Program, Workout) {
        let program = try makeStartedProgram(weeks: weeks)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        try finish(workout, of: program)
        return (program, workout)
    }

    /// Logs every working set still to do at 100 × 10, rates each exercise, then finishes the workout.
    private func finish(_ workout: Workout, of program: Program) throws {
        if workout.status == .planned { workout.startAndCascade() }
        for exercise in workout.workoutExercises {
            exercise.workingSets.filter { !$0.isDone }.forEach(log)
            exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
        }
        workout.skipRemainingSets()
        _ = program.finishWorkout(workout)
        try container.mainContext.save()
        #expect(workout.status == .complete)
    }

    private func makeStartedProgram(weeks: Int, days: Int = 1) throws -> Program {
        let context = container.mainContext
        let exercise = Exercise(
            exerciseName: "Bench",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 12
        )
        context.insert(exercise)
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: days, templateMuscleFocus: [.chest])
        for _ in 0..<days {
            template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        }
        context.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        try context.save()
        return program
    }
}
