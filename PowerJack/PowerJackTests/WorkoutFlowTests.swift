//
//  WorkoutFlowTests.swift
//  PowerJackTests
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WorkoutFlowTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()
    @Test("Finishing a workout moves on to the next workout in the week without starting it")
    func finishAdvancesWithinWeek() throws {
        let program = try makeStartedProgram(weeks: 2, workouts: 2)
        let first = try #require(program.nextWorkout)
        first.startAndCascade()
        log(first, reps: 10, weightTenthsPounds: 1000)

        let next = program.finishWorkout(first)

        #expect(first.status == .complete)
        #expect(next === program.programWeeks[0].workouts[1])
        // It waits for Start Workout.
        #expect(next?.status == .planned)
        #expect(program.programWeeks[1].workouts.isEmpty)
    }

    @Test("Finishing a week builds the next week with progressed prescriptions")
    func finishWeekBuildsProgression() throws {
        let program = try makeStartedProgram(weeks: 2, workouts: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        // Max reps 12 -> load threshold 11; 11 reps at 135 lb earns +5 lb.
        log(workout, reps: 11, weightTenthsPounds: 1350)

        let next = try #require(program.finishWorkout(workout))

        let weekTwo = program.programWeeks[1]
        #expect(program.programWeeks[0].status == .complete)
        #expect(weekTwo.status == .active)
        #expect(next === weekTwo.workouts.first)
        #expect(next.status == .planned)
        let sets = try #require(next.workoutExercises.first).workingSets
        #expect(sets.map(\.repsPlanned) == [11, 11])
        #expect(sets.map(\.weightTenthsPlannedPounds) == [1400, 1400])
        #expect(sets.allSatisfy { $0.status == .planned })
    }

    @Test("Severe pain holds the next exercise behind a check-in until resolved")
    func checkInLocksUntilResolved() throws {
        let program = try makeStartedProgram(weeks: 2, workouts: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        log(workout, reps: 10, weightTenthsPounds: 1000, pain: .severe)

        let next = try #require(program.finishWorkout(workout))
        let exercise = try #require(next.workoutExercises.first)

        #expect(exercise.checkInPending)
        #expect(exercise.checkInSourcePain == .severe)
        #expect(exercise.locked)
        #expect(exercise.status == .planned)
        #expect(exercise.workingSets.map(\.repsPlanned) == [10, 10])
        #expect(exercise.addSet() == nil)
        #expect(next.currentExerciseIndex == 0)

        exercise.resolveCheckIn(.reset)
        #expect(exercise.checkIn == .resolved)
        #expect(!exercise.locked)
        #expect(exercise.status == .active)
        #expect(exercise.workingSets.count == WorkoutExercise.initialSets)
        #expect(exercise.warmupSets.count == WorkoutExercise.initialWarmupSets)
        #expect(exercise.workingSets.allSatisfy { $0.repsPlanned == nil && $0.status == .active })
    }

    @Test("Resolving a check-in with continue keeps the held prescription")
    func checkInContinue() throws {
        let program = try makeStartedProgram(weeks: 2, workouts: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        log(workout, reps: 10, weightTenthsPounds: 1000, pain: .extreme)
        let exercise = try #require(program.finishWorkout(workout)?.workoutExercises.first)

        exercise.resolveCheckIn(.continue)

        #expect(exercise.status == .active)
        #expect(exercise.workingSets.map(\.weightTenthsPlannedPounds) == [1000, 1000])
        #expect(exercise.workoutSets.allSatisfy { $0.status == .active })
    }

    @Test("Finishing the last workout of the last week completes the program")
    func finishingProgram() throws {
        let program = try makeStartedProgram(weeks: 1, workouts: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        log(workout, reps: 10, weightTenthsPounds: 1000)

        #expect(program.finishWorkout(workout) == nil)
        #expect(program.status == .complete)
        #expect(program.nextWorkout == nil)
    }

    @Test("Skipping a planned workout advances the program")
    func skipWorkout() throws {
        let program = try makeStartedProgram(weeks: 1, workouts: 2)
        let first = program.programWeeks[0].workouts[0]

        let next = program.skipWorkout(first)

        #expect(first.status == .skipped)
        #expect(next === program.programWeeks[0].workouts[1])
    }

    @Test("Skipping the rest of a workout keeps finished sets and skips the others")
    func skipRestOfWorkoutKeepsCompletedSets() throws {
        let program = try makeStartedProgram(weeks: 1, workouts: 2, exercisesPerWorkout: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let workingSets = workout.workoutExercises.flatMap(\.workingSets)
        let finished = workingSets.prefix(3)
        for set in finished {
            set.reps = 8
            set.weightTenthsPounds = 1000
            set.complete()
        }

        let next = program.skipWorkout(workout)

        #expect(workout.status == .skipped)
        #expect(finished.allSatisfy { $0.status == .complete && $0.reps == 8 && $0.weightTenthsPounds == 1000 })
        #expect(workingSets.dropFirst(3).allSatisfy { $0.status == .skipped })
        #expect(workout.workoutExercises.flatMap(\.warmupSets).allSatisfy { $0.status == .skipped })
        #expect(workout.completedWorkingSets == 3)
        #expect(next === program.programWeeks[0].workouts[1])

        // The finished sets count toward training history.
        let logs = try container.mainContext.fetch(FetchDescriptor<WorkoutLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.sets(for: .chest) == 3)
    }

    @Test("Skipping a workout with nothing finished writes no history")
    func skipUntouchedWorkoutLogsNothing() throws {
        let program = try makeStartedProgram(weeks: 1, workouts: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()

        program.skipWorkout(workout)

        #expect(workout.workoutExercises.flatMap(\.workoutSets).allSatisfy { $0.status == .skipped })
        #expect(try container.mainContext.fetch(FetchDescriptor<WorkoutLog>()).isEmpty)
    }

    @Test("Current workout and exercise are restored from persisted state")
    func restoreFromStore() throws {
        let program = try makeStartedProgram(weeks: 2, workouts: 2, exercisesPerWorkout: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let firstExercise = workout.workoutExercises[0]
        for set in firstExercise.workoutSets {
            set.reps = 10
            set.weightTenthsPounds = 1000
            set.complete()
        }
        // All sets logged but no feedback yet: the user is still on exercise 0.
        #expect(workout.currentExerciseIndex == 0)
        #expect(firstExercise.needsFeedback)

        firstExercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .easy, levelOfPain: .none))
        firstExercise.completeAndCascade()
        try container.mainContext.save()

        // A fresh context stands in for a relaunch.
        let reloaded = try #require(try ModelContext(container).fetch(FetchDescriptor<Program>()).first)
        let restoredWorkout = try #require(reloaded.nextWorkout)
        #expect(restoredWorkout.status == .active)
        #expect(restoredWorkout.order == 0)
        #expect(restoredWorkout.currentExerciseIndex == 1)
        #expect(reloaded.weekNumber(containing: restoredWorkout) == 1)
    }

    @Test("Logged reps above 30 are never saved")
    func repsCap() throws {
        let set = WorkoutSet(order: 0, plannedReps: 31, plannedWeightTenthsPounds: nil)
        #expect(set.repsPlanned == nil)
        set.start()
        set.reps = 30
        #expect(set.reps == 30)
        set.reps = 31
        #expect(set.reps == nil)
    }

    @Test("A weight entered on a set carries to later sets that aren't done yet")
    func weightCarriesForward() throws {
        let program = try makeStartedProgram(weeks: 1, workouts: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)
        _ = exercise.addSet()
        _ = exercise.addSet()
        let sets = exercise.workingSets
        try #require(sets.count == 4)

        sets[0].weightTenthsPounds = 2000
        sets[0].complete()
        // A later set that is already logged keeps its own weight.
        sets[3].weightTenthsPounds = 1500
        sets[3].complete()

        sets[1].weightTenthsPounds = 2200
        exercise.applyWeight(2200, after: sets[1])

        #expect(sets.map(\.weightTenthsPounds) == [2000, 2200, 2200, 1500])
    }

    @Test("The last set of an exercise waits three times longer before auto-completing")
    func lastSetAutoCompleteDelay() {
        #expect(WorkoutSetView.autoCompleteDelay(isLastSet: false) == .milliseconds(1200))
        #expect(WorkoutSetView.autoCompleteDelay(isLastSet: true) == .milliseconds(3600))
    }

    @Test("The seeded week two matches the documented progression rules")
    func seededWeekTwo() {
        let scenario = PowerJackSeed.weekTwoProgression()
        let week = scenario.weekTwoWorkouts
        let bench = week[0].workoutExercises[0].workingSets
        let pullUp = week[1].workoutExercises[0].workingSets
        let pulldown = week[1].workoutExercises[1].workingSets

        #expect(bench.map(\.weightTenthsPlannedPounds) == [1400, 1400])
        #expect(scenario.checkInExercise.checkInPending)
        #expect(pullUp.map(\.repsPlanned) == [9, 8])
        #expect(pulldown.map(\.repsPlanned) == [10, 5])
        #expect(scenario.program.nextWorkout === week[0])
    }

    // MARK: Helpers

    private func makeStartedProgram(
        weeks: Int,
        workouts: Int,
        exercisesPerWorkout: Int = 1
    ) throws -> Program {
        let context = container.mainContext
        let exercise = Exercise(
            exerciseName: "Bench",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 12
        )
        context.insert(exercise)

        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: workouts, templateMuscleFocus: [.back])
        template.templateWorkoutsValue = (0..<workouts).map { order in
            let workout = TemplateWorkout(order: order)
            workout.templateExercisesValue = (0..<exercisesPerWorkout).map {
                TemplateExercise(exercise: exercise, order: $0)
            }
            return workout
        }
        context.insert(template)

        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        return program
    }

    private func log(
        _ workout: Workout,
        reps: Int,
        weightTenthsPounds: Int,
        pain: LevelOfPain = .none,
        effort: LevelOfEffort = .challenge
    ) {
        for exercise in workout.workoutExercises {
            for set in exercise.workoutSets {
                set.reps = reps
                set.weightTenthsPounds = weightTenthsPounds
                set.complete()
            }
            exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: effort, levelOfPain: pain))
            exercise.completeAndCascade()
        }
    }
}
