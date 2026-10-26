//
//  WarmupHintTests.swift
//  PowerJackTests
//
//  Build workouts explain warming up in the lifter's first two weeks, counted across every program.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WarmupHintTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private static let day = 86_400.0

    @Test("Two exercises show the hint in week 1, one in week 2, then none")
    func exercisesByWeek() {
        #expect([0, 6, 7, 13, 14, 60].map { WorkoutExercise.warmupHintExercises(daysIntoTraining: $0) } == [2, 2, 1, 1, 0, 0])
    }

    @Test("A new lifter's first Build workout shows the hint on its first two exercises")
    func firstWorkoutShowsTwo() throws {
        let workout = try #require(makeProgram().nextWorkout)

        #expect(workout.workoutExercises.map(\.showsWarmupHint) == [true, true, false])
    }

    @Test("Week 2 counts from the first set logged in any program, not the program's own weeks")
    func secondWeekAcrossPrograms() throws {
        try logSet(daysAgo: 8, in: makeProgram())
        let workout = try #require(makeProgram().nextWorkout)

        #expect(workout.workoutExercises.map(\.showsWarmupHint) == [true, false, false])
    }

    @Test("After two weeks of training, no workout shows the hint")
    func goneAfterTwoWeeks() throws {
        try logSet(daysAgo: 14, in: makeProgram())
        let workout = try #require(makeProgram().nextWorkout)

        #expect(workout.workoutExercises.allSatisfy { !$0.showsWarmupHint })
    }

    @Test("A finished workout keeps the hint it had when it was done")
    func pastWorkoutKeepsHint() throws {
        let program = try makeProgram()
        try logSet(daysAgo: 20, in: program)
        let workout = try #require(program.programWeeks.first?.workouts.first)

        #expect(workout.workoutExercises.map(\.showsWarmupHint) == [true, true, false])
    }

    @Test("Only Build programs show the hint")
    func buildOnly() throws {
        for type in [TemplateType.strength, .powerJack] {
            let workout = try #require(makeProgram(type: type).nextWorkout)
            #expect(workout.workoutExercises.allSatisfy { !$0.showsWarmupHint })
        }
    }

    private func makeProgram(type: TemplateType = .hypertrophy) throws -> Program {
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [], templateType: type)
        let day = template.addTemplateWorkout()
        for (name, muscle) in [("Bench", Muscle.chest), ("Row", .back), ("Squat", .quads)] {
            let exercise = Exercise(
                exerciseName: name,
                exerciseEquipment: .barbell,
                primaryMuscleFocus: muscle,
                minReps: 6,
                maxReps: 12
            )
            container.mainContext.insert(exercise)
            day.addTemplateExercise(exercise: exercise)
        }
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: 2, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        program.start()
        return program
    }

    /// Logs the first warmup of the program's next workout, `daysAgo` days back.
    private func logSet(daysAgo: Int, in program: Program) throws {
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let set = try #require(workout.workoutExercises.first?.warmupSets.first)
        set.reps = 5
        set.weightTenthsPounds = 450
        set.complete(at: .now.addingTimeInterval(-Double(daysAgo) * Self.day))
        try container.mainContext.save()
    }
}
