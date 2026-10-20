//
//  PowerJackPlannerTests.swift
//  PowerJackTests
//
//  PowerJack programs end to end: week 1 from the engine, then each week from the logs.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct PowerJackPlannerTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("Week 1 calibrates main lifts: a TOP set and BACK sets the lifter loads at 3 reps left")
    func firstWeek() throws {
        let program = try makeProgram()
        let week = try #require(program.programWeeks.first)
        let squat = try #require(week.workouts.first?.workoutExercises.first)

        #expect(week.weekKind == .build)
        #expect(week.blockWeek == 1)
        #expect(squat.topSets == 1)
        #expect(squat.calibrating)
        #expect(squat.rirTarget == 3)
        #expect(squat.workingSets.map(\.repsPlanned) == [5, 8, 8, 8, 8])
        #expect(squat.workingSets.allSatisfy { $0.weightTenthsPlannedPounds == nil })
        #expect(squat.warmupSets.count == 3)
        #expect(squat.progressionNote != nil)

        // The curl is an accessory: its range starts at 12 reps at Low fatigue.
        let curl = try #require(week.workouts.first?.workoutExercises.last)
        #expect(curl.powerJackRole == .accessory)
        #expect(curl.workingSets.allSatisfy { $0.repsPlanned == 12 })
    }

    @Test("After the calibrating week, loads come from the new anchors")
    func calibratedSecondWeek() throws {
        let program = try makeProgram()
        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let squat = try #require(workout.workoutExercises.first)
        for (index, set) in squat.workingSets.enumerated() {
            set.weightTenthsPounds = index == 0 ? 2250 : 1850
            squat.completeSet(set)
            if index == 0 {
                #expect(squat.needsTopSetRating)
                squat.rateTopSets(.three)
            }
        }
        squat.addFeedback(feedback: ExerciseFeedback(repsInReserve: .three, levelOfPain: .none))
        for exercise in workout.workoutExercises.dropFirst() {
            for set in exercise.workingSets {
                set.weightTenthsPounds = 300
                exercise.completeSet(set)
            }
            exercise.addFeedback(feedback: ExerciseFeedback(repsInReserve: .two, levelOfPain: .none))
        }
        program.finishWorkout(workout)

        let weekTwo = program.programWeeks[1]
        let next = try #require(weekTwo.workouts.first?.workoutExercises.first)
        #expect(weekTwo.weekKind == .build)
        // 225 x 5 at 3 left anchors at 268.9; a 4-week program's week 2 aims at 2 left: 230.
        #expect(next.workingSets.first?.weightTenthsPlannedPounds == 2300)
        #expect(next.workingSets.dropFirst().allSatisfy { $0.weightTenthsPlannedPounds == 1850 })
        #expect(next.rirTarget == 2)
        #expect(!next.calibrating)
    }

    @Test("Every built-in PowerJack template starts with sets and targets on every exercise")
    func catalogTemplates() throws {
        try ExerciseCatalog.seed(in: container.mainContext)
        try TemplateCatalog.seed(in: container.mainContext)
        let templates = try container.mainContext.fetch(FetchDescriptor<TemplateProgram>())
            .filter { $0.templateType == .powerJack }
        #expect(!templates.isEmpty)
        for template in templates {
            let program = Program(programLengthWeeks: 8, templateProgram: template)
            for exercise in program.programWeeks[0].workouts.flatMap(\.workoutExercises) {
                #expect(!exercise.workingSets.isEmpty, "\(template.templateName)")
                #expect(exercise.workingSets.count <= WorkoutExercise.maxSets)
                #expect(exercise.rirTarget != nil, "\(template.templateName)")
            }
            // Main lifts are read from the template: one per main pattern at most.
            let mains = Set(program.programWeeks[0].workouts.flatMap(\.workoutExercises)
                .filter { $0.powerJackRole == .main }.compactMap { $0.exercise?.catalogID })
            #expect(mains.count <= PowerJackRules.mainLiftsMax)
            #expect(mains.contains("barbell-bench-press"), "\(template.templateName)")
        }
    }

    // MARK: Helpers

    private func makeProgram() throws -> Program {
        let squat = Exercise(exerciseName: "Squat", exerciseEquipment: .barbell, primaryMuscleFocus: .quads, fatigueLevel: .high)
        let curl = Exercise(exerciseName: "Curl", exerciseEquipment: .dumbbell, primaryMuscleFocus: .biceps, fatigueLevel: .low)
        container.mainContext.insert(squat)
        container.mainContext.insert(curl)
        let template = TemplateProgram(templateName: "Jack", workoutsPerWeek: 1, templateMuscleFocus: [], templateType: .powerJack)
        let day = template.addTemplateWorkout()
        day.addTemplateExercise(exercise: squat)
        day.addTemplateExercise(exercise: curl)
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: 4, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        program.start()
        return program
    }
}
