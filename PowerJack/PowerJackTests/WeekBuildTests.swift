//
//  WeekBuildTests.swift
//  PowerJackTests
//
//  What every planner's `build` shares (`WeekPlanner.buildIndex` and `copyDays`): which week it can
//  fill, and the days, exercises and per-day settings it copies from the week before.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WeekBuildTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("Only an empty week that follows another one can be built")
    func buildIndex() throws {
        let program = try makeProgram(templateType: .hypertrophy, weeks: 3)
        let weeks = program.programWeeks

        #expect(ProgressionPlanner.buildIndex(of: weeks[0], in: program) == nil)
        #expect(ProgressionPlanner.buildIndex(of: weeks[1], in: program) == 1)
        #expect(ProgressionPlanner.buildIndex(of: weeks[2], in: program) == 2)
        #expect(ProgressionPlanner.buildIndex(of: ProgramWeek(order: 7), in: program) == nil)

        _ = weeks[1].addWorkout()
        #expect(ProgressionPlanner.buildIndex(of: weeks[1], in: program) == nil)
    }

    @Test("Copying days keeps their order and each exercise's warmup setting and superset")
    func copyDays() throws {
        let program = try makeProgram(templateType: .hypertrophy, weeks: 2)
        let weeks = program.programWeeks
        let first = weeks[0].workouts[0].workoutExercises
        first[0].disableWarmups()
        let superset = UUID()
        first[0].setSuperset(superset)
        first[1].setSuperset(superset)
        var copied: [(String?, Int)] = []

        ProgressionPlanner.copyDays(of: weeks[0], into: weeks[1]) { workoutExercise, sourceExercise, sourceWorkout in
            #expect(workoutExercise.exercise === sourceExercise.exercise)
            copied.append((workoutExercise.exercise?.exerciseName, sourceWorkout.order))
        }

        #expect(copied.map(\.0) == ["Bench", "Row", "Squat"])
        #expect(copied.map(\.1) == [0, 0, 1])
        let built = weeks[1].workouts.map(\.workoutExercises)
        #expect(built.map(\.count) == [2, 1])
        #expect(built[0][0].warmupsDisabled)
        #expect(!built[0][1].warmupsDisabled)
        #expect(built[0][0].supersetID == superset)
        #expect(built[0][1].supersetID == superset)
        #expect(built[1][0].supersetID == nil)
    }

    @Test("Each kind of program builds next week with last week's days and warmup settings", arguments: TemplateType.allCases)
    func nextWeekKeepsDays(templateType: TemplateType) throws {
        let program = try makeProgram(templateType: templateType, weeks: 2)
        program.start()
        let weekOne = program.programWeeks[0]
        weekOne.workouts[1].workoutExercises[0].disableWarmups()

        for workout in weekOne.workouts {
            program.skipWorkout(workout)
        }

        let weekTwo = program.programWeeks[1]
        let names = { (week: ProgramWeek) in week.workouts.map { $0.workoutExercises.map { $0.exercise?.exerciseName } } }
        #expect(names(weekTwo) == names(weekOne))
        #expect(weekTwo.workouts.map { $0.workoutExercises.map(\.warmupsDisabled) } == [[false, false], [true]])
    }

    // MARK: Helpers

    /// Two days: Bench and Row, then Squat.
    private func makeProgram(templateType: TemplateType, weeks: Int) throws -> Program {
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 2, templateMuscleFocus: [.chest], templateType: templateType)
        let dayOne = template.addTemplateWorkout()
        dayOne.addTemplateExercise(exercise: makeExercise("Bench", primary: .chest))
        dayOne.addTemplateExercise(exercise: makeExercise("Row", primary: .back))
        template.addTemplateWorkout().addTemplateExercise(exercise: makeExercise("Squat", primary: .quads))
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        return program
    }

    private func makeExercise(_ name: String, primary: Muscle) -> Exercise {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: .barbell, primaryMuscleFocus: primary)
        container.mainContext.insert(exercise)
        return exercise
    }
}
