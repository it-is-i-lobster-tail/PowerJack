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

    @Test("Two easy weeks on a focus muscle add a set in week three")
    func focusVolumeInWeekThree() throws {
        let program = try makeProgram(weeks: 4, focus: [.chest])
        try finishWeeks(2, of: program)

        let sets = try #require(program.nextWorkout?.workoutExercises.first).workingSets
        #expect(program.weekNumber(containing: try #require(program.nextWorkout)) == 3)
        #expect(sets.count == 3)
        #expect(sets.last?.repsPlanned == 6)
        #expect(sets.last?.weightTenthsPlannedPounds == 1000)
    }

    @Test("A non-focus muscle needs a third easy week before it adds a set")
    func nonFocusVolumeNeedsThreeWeeks() throws {
        let program = try makeProgram(weeks: 6, focus: [.back])
        try finishWeeks(2, of: program)
        #expect(try #require(program.nextWorkout?.workoutExercises.first).workingSets.count == 2)

        try finishWeeks(1, of: program)
        #expect(try #require(program.nextWorkout?.workoutExercises.first).workingSets.count == 3)
    }

    @Test("A swapped exercise starts its history over")
    func changedExerciseHasNoHistory() throws {
        let program = try makeProgram(weeks: 4, focus: [.chest])
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

    private func makeProgram(weeks: Int, focus: [Muscle]) throws -> Program {
        let exercise = Exercise(
            exerciseName: "Bench",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 12
        )
        container.mainContext.insert(exercise)
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: focus)
        template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        program.start()
        return program
    }

    /// Logs every set at 8 reps and 100 lb with easy, pain-free feedback, then finishes the workout.
    private func finishWeeks(_ count: Int, of program: Program) throws {
        for _ in 0..<count {
            let workout = try #require(program.nextWorkout)
            if workout.status == .planned { workout.startAndCascade() }
            for exercise in workout.workoutExercises {
                for set in exercise.workoutSets {
                    set.reps = 8
                    set.weightTenthsPounds = 1000
                    set.complete()
                }
                exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .easy, levelOfPain: .none))
                exercise.completeAndCascade()
            }
            program.finishWorkout(workout)
        }
    }
}
