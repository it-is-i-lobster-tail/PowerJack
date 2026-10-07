//
//  WarmupSetTests.swift
//  PowerJackTests
//
//  Warmup sets come first, are logged like any set, and never count toward progression.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WarmupSetTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("Every exercise starts with two warmups ahead of its working sets")
    func newProgramStartsWithWarmups() throws {
        let program = try makeProgram(weeks: 1)
        let exercise = try #require(program.nextWorkout?.workoutExercises.first)

        #expect(exercise.workoutSets.map(\.setType) == [.warmup, .warmup, .working, .working])
        #expect(exercise.warmupSets.map { exercise.number(of: $0) } == [1, 2])
        #expect(exercise.workingSets.map { exercise.number(of: $0) } == [1, 2])
    }

    @Test("Warmups don't change next week's working sets")
    func warmupsSkipProgression() throws {
        let program = try makeProgram(weeks: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)
        // Warmups well under the minimum reps would hold progression if they counted.
        log(exercise.warmupSets, reps: 3, weightTenthsPounds: 450)
        log(exercise.workingSets, reps: 11, weightTenthsPounds: 1350)
        exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))

        let next = try #require(program.finishWorkout(workout)?.workoutExercises.first)

        #expect(next.workingSets.map(\.weightTenthsPlannedPounds) == [1400, 1400])
        // Warmups repeat what was logged.
        #expect(next.warmupSets.map(\.repsPlanned) == [3, 3])
        #expect(next.warmupSets.map(\.weightTenthsPlannedPounds) == [450, 450])
    }

    @Test("Weekly muscle volume and the summary chart count working sets only")
    func warmupsSkipVolumeAndSummary() throws {
        let program = try makeProgram(weeks: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)
        log(exercise.workoutSets, reps: 8, weightTenthsPounds: 1000)

        #expect(workout.completedSetsByMuscle == [MuscleSetCount(muscle: .chest, sets: 2)])
        let week = try #require(program.programWeeks.first)
        #expect(ProgressionPlanner.muscleSetCredits(in: week)[.chest] == 2)
        #expect(ProgressionPlanner.history(exercise, programWeek: 1).sets.count == 2)
    }

    @Test("An exercise is finished once its working sets are done, warmups or not")
    func warmupsAreOptional() throws {
        let program = try makeProgram(weeks: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)

        log(exercise.workingSets, reps: 8, weightTenthsPounds: 1000)
        #expect(exercise.allSetsDone())
        #expect(exercise.needsFeedback)
        #expect(workout.currentSet == nil)
        #expect(workout.completedWorkingSets == workout.workingSetCount)

        exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
        exercise.completeAndCascade()

        #expect(exercise.status == .complete)
        // Unlogged warmups are skipped, not recorded as done.
        #expect(exercise.warmupSets.map(\.status) == [.skipped, .skipped])
        #expect(exercise.workingSets.map(\.status) == [.complete, .complete])
    }

    @Test("Warmups alone don't finish an exercise")
    func warmupsDontFinishExercise() throws {
        let program = try makeProgram(weeks: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)

        log(exercise.warmupSets, reps: 5, weightTenthsPounds: 450)

        #expect(!exercise.allSetsDone())
        #expect(workout.completedWorkingSets == 0)
    }

    @Test("A warmup weight only fills the next warmup")
    func warmupWeightStaysInWarmups() throws {
        let program = try makeProgram(weeks: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)
        let first = exercise.workoutSets[0]

        first.weightTenthsPounds = 950
        exercise.applyWeight(950, after: first)

        #expect(exercise.workoutSets.map(\.weightTenthsPounds) == [950, 950, nil, nil])
    }

    @Test("Adding and removing sets only touches working sets")
    func addAndRemoveWorkingSets() throws {
        let program = try makeProgram(weeks: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)

        while exercise.addSet() != nil {}
        #expect(exercise.workingSets.count == WorkoutExercise.maxSets)

        for _ in 0..<(WorkoutExercise.maxSets + 1) { exercise.removeLastSet() }
        #expect(exercise.workingSets.isEmpty)
        #expect(exercise.warmupSets.count == WorkoutExercise.initialWarmupSets)
    }

    @Test("A warmup added mid-exercise slots in ahead of the working sets, up to the cap")
    func addWarmupAfterWorkingSets() throws {
        let program = try makeProgram(weeks: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)

        while exercise.addWarmupSet() != nil {}

        #expect(exercise.warmupSets.count == WorkoutExercise.maxWarmupSets)
        #expect(exercise.workoutSets.map(\.setType) == [.warmup, .warmup, .warmup, .warmup, .working, .working])
        #expect(exercise.workoutSets.map(\.order) == Array(0..<6))

        exercise.removeLastSet(type: .warmup)
        #expect(exercise.warmupSets.count == WorkoutExercise.maxWarmupSets - 1)
        #expect(exercise.workingSets.count == WorkoutExercise.initialSets)
    }

    @Test("Skip Warmup skips only the warmups still to do")
    func skipWarmups() throws {
        let program = try makeProgram(weeks: 1)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)
        log([exercise.warmupSets[0]], reps: 5, weightTenthsPounds: 450)

        exercise.skipWarmups()

        #expect(exercise.warmupSets.map(\.status) == [.complete, .skipped])
        #expect(exercise.workingSets.allSatisfy { $0.status == .active })
    }

    @Test("Disabling warmups drops the unlogged ones here and in later weeks, until one is added back")
    func disableWarmups() throws {
        let program = try makeProgram(weeks: 3)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)
        log([exercise.warmupSets[0]], reps: 5, weightTenthsPounds: 450)

        exercise.disableWarmups()
        #expect(exercise.exercise?.warmupDisabled == true)
        #expect(exercise.warmupSets.count == 1)
        #expect(exercise.addSet(type: .warmup) == nil)

        log(exercise.workingSets, reps: 10, weightTenthsPounds: 1350)
        exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
        let weekTwo = try #require(program.finishWorkout(workout))
        let next = try #require(weekTwo.workoutExercises.first)
        #expect(next.warmupSets.isEmpty)

        weekTwo.startAndCascade()
        #expect(next.addWarmupSet() != nil)
        #expect(next.exercise?.warmupDisabled == false)
    }

    @Test("Next week repeats how many warmups were done")
    func warmupCountCarriesOver() throws {
        let program = try makeProgram(weeks: 2)
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let exercise = try #require(workout.workoutExercises.first)
        _ = exercise.addWarmupSet()
        log(exercise.workoutSets, reps: 8, weightTenthsPounds: 1000)
        exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))

        let next = try #require(program.finishWorkout(workout)?.workoutExercises.first)

        #expect(next.warmupSets.count == 3)
    }

    // MARK: Helpers

    private func makeProgram(weeks: Int) throws -> Program {
        let exercise = Exercise(
            exerciseName: "Bench",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 12
        )
        container.mainContext.insert(exercise)
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [])
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        program.start()
        return program
    }

    private func log(_ sets: [WorkoutSet], reps: Int, weightTenthsPounds: Int) {
        for set in sets {
            set.reps = reps
            set.weightTenthsPounds = weightTenthsPounds
            set.complete()
        }
    }
}
