//
//  ProgressionPlannerTests.swift
//  PowerJackTests
//
//  Building later weeks from the history of earlier ones.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ProgressionPlannerTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("One clean week on a focus muscle adds a set in week two, on top of a rep on every set")
    func focusVolumeInWeekTwo() throws {
        let program = try makeProgram(weeks: 4, focus: [.chest])
        try finishWeeks(1, of: program)

        let sets = try #require(program.nextWorkout?.workoutExercises.first).workingSets
        #expect(program.weekNumber(containing: try #require(program.nextWorkout)) == 2)
        #expect(sets.map(\.repsPlanned) == [9, 9, 6])
        #expect(sets.map(\.weightTenthsPlannedPounds) == [1000, 1000, 1000])
    }

    @Test("A non-focus muscle needs a second clean week before it adds a set")
    func nonFocusVolumeNeedsTwoWeeks() throws {
        let program = try makeProgram(weeks: 6, focus: [.back])
        try finishWeeks(1, of: program)
        #expect(try #require(program.nextWorkout?.workoutExercises.first).workingSets.count == 2)

        try finishWeeks(1, of: program)
        #expect(try #require(program.nextWorkout?.workoutExercises.first).workingSets.count == 3)
    }

    @Test("A bodyweight exercise banks half reps from week to week")
    func bodyweightBanksHalfReps() throws {
        let program = try makeProgram(weeks: 4, focus: [.back], exercise: Exercise(
            exerciseName: "Push Up",
            exerciseEquipment: .bodyweight,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 30
        ))
        // 8 reps with 3 left each week: 9 next, then 10 once the banked half rep makes a whole one.
        try finishWeeks(1, of: program, weightTenthsPounds: nil)
        #expect(try #require(program.nextWorkout?.workoutExercises.first).workingSets.map(\.repsPlanned) == [9, 9])

        try finishWeeks(1, of: program, weightTenthsPounds: nil)
        #expect(try #require(program.nextWorkout?.workoutExercises.first).workingSets.prefix(2).map(\.repsPlanned) == [10, 10])
    }

    @Test("A swapped exercise starts its history over")
    func changedExerciseHasNoHistory() throws {
        // Chest isn't a focus muscle, so a set would take two clean weeks of the same exercise.
        let program = try makeProgram(weeks: 4, focus: [.back])
        try finishWeeks(1, of: program)

        // Week two swaps to another chest exercise, so week one no longer matches.
        let weekTwo = try #require(program.nextWorkout)
        let swap = Exercise(exerciseName: "Dip", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        container.mainContext.insert(swap)
        weekTwo.workoutExercises.first?.changeExercise(newExercise: swap)
        try finishWeeks(1, of: program)

        let sets = try #require(program.nextWorkout?.workoutExercises.first).workingSets
        #expect(program.nextWorkout?.workoutExercises.first?.exercise === swap)
        #expect(sets.count == 2)
    }

    @Test("Only an empty week that follows another can be built")
    func buildGuards() throws {
        let program = try makeProgram(weeks: 2, focus: [.chest])
        let weekOne = program.programWeeks[0]
        let workoutsBefore = weekOne.workouts.count

        ProgressionPlanner.build(weekOne, in: program)
        ProgressionPlanner.build(ProgramWeek(order: 5), in: program)
        #expect(weekOne.workouts.count == workoutsBefore)
    }

    // MARK: Helpers

    private func makeProgram(weeks: Int, focus: [Muscle], exercise: Exercise? = nil) throws -> Program {
        let exercise = exercise ?? Exercise(
            exerciseName: "Bench",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 12
        )
        container.mainContext.insert(exercise)
        // Every type now has its own planner, so `finishWeeks` builds the next week with this one directly.
        let template = TemplateProgram(
            templateName: "Test",
            workoutsPerWeek: 1,
            templateMuscleFocus: focus,
            templateType: .strength
        )
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        program.start()
        return program
    }

    /// Logs every set at 8 reps and 100 lb, or `weightTenthsPounds`, with easy, pain-free feedback, then finishes the workout.
    private func finishWeeks(_ count: Int, of program: Program, weightTenthsPounds: Int? = 1000) throws {
        for _ in 0..<count {
            let workout = try #require(program.nextWorkout)
            if workout.status == .planned { workout.startAndCascade() }
            for exercise in workout.workoutExercises {
                for set in exercise.workoutSets {
                    set.reps = 8
                    set.weightTenthsPounds = weightTenthsPounds
                    set.complete()
                }
                exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .easy, levelOfPain: .none))
                exercise.completeAndCascade()
            }
            if let week = program.programWeek(containing: workout),
               week.workouts.allSatisfy({ $0 === workout || $0.isFinished }),
               let nextWeek = program.programWeeks.first(where: { $0.order == week.order + 1 }),
               nextWeek.workouts.isEmpty {
                ProgressionPlanner.build(nextWeek, in: program)
            }
            program.finishWorkout(workout)
        }
    }
}
