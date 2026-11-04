//
//  BuildProgramTests.swift
//  PowerJackTests
//
//  Build programs on the original per-set rules (`ProgressionPlanner`), including programs whose earlier
//  weeks the Build engine planned.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct BuildProgramTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("A Build program's week 1 keeps the template's sets, with no aim or block")
    func firstWeek() throws {
        let program = try makeProgram(weeks: 2, exercise: bench())
        let week = try #require(program.programWeeks.first)
        let exercise = try #require(week.workouts.first?.workoutExercises.first)

        #expect(week.weekKind == nil)
        #expect(exercise.rirTarget == nil)
        #expect(exercise.progressionNote == nil)
        #expect(exercise.workingSets.count == 2)
        #expect(exercise.workingSets.allSatisfy { $0.repsPlanned == nil && $0.weightTenthsPlannedPounds == nil })
    }

    @Test("Each set progresses from its own reps: a pull-up logged 7 and 5 plans 8 and 6")
    func eachSetAddsARep() throws {
        let pullUp = Exercise(exerciseName: "Pull Up", exerciseEquipment: .bodyweight, primaryMuscleFocus: .back)
        let program = try makeProgram(weeks: 2, exercise: pullUp)

        let weekOne = try #require(program.nextWorkout)
        log(weekOne, reps: [7, 5], weightTenthsPounds: nil, repsLeft: .three)
        let weekTwo = try #require(program.finishWorkout(weekOne)?.workoutExercises.first)

        #expect(weekTwo.workingSets.map(\.repsPlanned) == [8, 6])
        #expect(weekTwo.workingSets.allSatisfy { $0.weightTenthsPlannedPounds == nil })
        #expect(weekTwo.rirTarget == nil)
    }

    @Test("A program the Build engine planned builds its next week on the per-set rules, then finishes")
    func upgradeFromBuildEngine() throws {
        let program = try makeProgram(weeks: 3, exercise: bench())
        let weeks = program.programWeeks
        // Before this change, the Build engine set up week 1 and wrote week 2.
        BuildPlanner.setUpFirstWeek(weeks[0], in: program)
        let weekOne = try #require(program.nextWorkout)
        log(weekOne, reps: [10, 10], weightTenthsPounds: 1000, repsLeft: .three)
        BuildPlanner.build(weeks[1], in: program)
        let weekTwo = try #require(program.finishWorkout(weekOne))
        let builtByEngine = try #require(weekTwo.workoutExercises.first)
        #expect(weeks[1].weekKind == .build)
        #expect(builtByEngine.rirTarget != nil)

        let loads = builtByEngine.workingSets.map { $0.weightTenthsPlannedPounds ?? 1000 }
        log(weekTwo, reps: [8], weightTenthsPounds: 1000, repsLeft: .three)
        let weekThree = try #require(program.finishWorkout(weekTwo))
        let next = try #require(weekThree.workoutExercises.first)

        // Week 2 keeps what the engine wrote; week 3 adds a rep to every set and shows no aim.
        #expect(builtByEngine.rirTarget != nil)
        #expect(weeks[2].weekKind == nil)
        #expect(next.rirTarget == nil)
        #expect(next.progressionNote == nil)
        #expect(next.workingSets.map(\.repsPlanned) == loads.map { _ in 9 })
        #expect(next.workingSets.map(\.weightTenthsPlannedPounds) == loads)

        log(weekThree, reps: [9], weightTenthsPounds: 1000, repsLeft: .three)
        #expect(program.finishWorkout(weekThree) == nil)
        #expect(program.status == .complete)
    }

    @Test("A long break leaves the next week as planned")
    func breakKeepsWeek() throws {
        let program = try makeProgram(weeks: 2, exercise: bench())
        let weekOne = try #require(program.nextWorkout)
        log(weekOne, reps: [10, 10], weightTenthsPounds: 1000, repsLeft: .three)
        let weekTwo = try #require(program.finishWorkout(weekOne))
        let before = weekTwo.workoutExercises.first?.workingSets.map(\.weightTenthsPlannedPounds)

        program.prepareToStart(weekTwo, at: .now.addingTimeInterval(30 * 86_400))

        #expect(program.programWeek(containing: weekTwo)?.weekKind == nil)
        #expect(weekTwo.workoutExercises.first?.workingSets.map(\.weightTenthsPlannedPounds) == before)
    }

    @Test("RIR-01: Build feedback asks for reps left and saves them on the version 2 scale")
    func feedbackDraft() throws {
        let program = try makeProgram(weeks: 1, exercise: bench())
        let exercise = try #require(program.programWeeks.first?.workouts.first?.workoutExercises.first)
        #expect(exercise.templateType?.ratesRepsInReserve == true)

        var draft = FeedbackDraft(ratesRepsInReserve: true)
        draft.levelOfPain = .mild
        #expect(!draft.canSave)
        draft.repsInReserve = .fiveOrMore
        let feedback = try #require(draft.makeFeedback())
        #expect(feedback.repsInReserve == .fiveOrMore)
        #expect(feedback.effortScaleVersion == RepsInReserve.scaleVersion)
    }

    @Test("Reset Progression plans this week's unstarted workouts again and leaves a started one alone")
    func resetRewritesUnstartedWorkouts() throws {
        let program = try makeProgram(weeks: 2, exercises: [[bench()], [pullUp()]])
        #expect(!program.canResetProgression)

        while let workout = program.nextWorkout, program.programWeek(containing: workout)?.order == 0 {
            log(workout, reps: [10, 8], weightTenthsPounds: 1000, repsLeft: .two)
            program.finishWorkout(workout)
        }
        let weekTwo = program.programWeeks[1].workouts
        let built = weekTwo.map(\.planSummary)

        // Day 1 is underway with a weight changed; day 2 hasn't started and its sets were changed.
        let started = weekTwo[0]
        started.startAndCascade()
        let startedSet = try #require(started.workoutExercises.first?.workingSets.first)
        startedSet.weightTenthsPounds = 1234
        let edited = try #require(weekTwo[1].workoutExercises.first)
        edited.replacePlannedWorkingSets([(reps: 3, weightTenthsPounds: 500)])
        edited.setProgression(rirTarget: 4, code: "edited", note: "Edited")
        #expect(weekTwo[1].planSummary != built[1])

        #expect(program.canResetProgression)
        program.resetProgression()

        #expect(weekTwo[1].planSummary == built[1])
        #expect(edited.progressionNote == nil)
        #expect(started.status == .active)
        #expect(startedSet.weightTenthsPounds == 1234)
        #expect(started.workoutExercises.first?.workingSets.count == 2)
    }

    @Test("Reset Progression rewrites a week the Build engine planned with the per-set rules")
    func resetMovesBuildEngineWeekToPerSetRules() throws {
        let fresh = try makeProgram(weeks: 2, exercise: bench())
        let fromEngine = try makeProgram(weeks: 2, exercise: bench())
        for program in [fresh, fromEngine] {
            let weekOne = try #require(program.nextWorkout)
            log(weekOne, reps: [10, 9], weightTenthsPounds: 1000, repsLeft: .two)
            if program === fromEngine {
                // Before Build went back to the per-set rules, the Build engine wrote week 2.
                BuildPlanner.build(program.programWeeks[1], in: program)
            }
            program.finishWorkout(weekOne)
        }
        let engineWeek = fromEngine.programWeeks[1]
        let engineWorkout = try #require(engineWeek.workouts.first)
        #expect(engineWeek.weekKind == .build)
        #expect(engineWorkout.workoutExercises.first?.rirTarget != nil)

        fromEngine.resetProgression()

        let freshWorkout = try #require(fresh.programWeeks[1].workouts.first)
        #expect(engineWorkout.planSummary == freshWorkout.planSummary)
        #expect(engineWorkout.workoutExercises.first?.progressionNote == nil)
        #expect(engineWeek.weekKind == nil)
    }

    // MARK: Helpers

    private func pullUp() -> Exercise {
        Exercise(exerciseName: "Pull Up", exerciseEquipment: .bodyweight, primaryMuscleFocus: .back)
    }

    private func bench() -> Exercise {
        Exercise(
            exerciseName: "Bench",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 12,
            fatigueLevel: .high
        )
    }

    /// A Build program with one workout of `exercise`. Chest isn't a focus muscle, so no sets are added.
    private func makeProgram(weeks: Int, exercise: Exercise) throws -> Program {
        try makeProgram(weeks: weeks, exercises: [[exercise]])
    }

    /// A Build program with a workout for each list of `exercises`.
    private func makeProgram(weeks: Int, exercises: [[Exercise]]) throws -> Program {
        let context = container.mainContext
        let template = TemplateProgram(templateName: "Build", workoutsPerWeek: exercises.count, templateMuscleFocus: [.back])
        for day in exercises {
            let workout = template.addTemplateWorkout()
            for exercise in day {
                context.insert(exercise)
                workout.addTemplateExercise(exercise: exercise)
            }
        }
        context.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        return program
    }

    /// Logs each working set with its reps (the last repeating) at its planned weight, or `weightTenthsPounds`
    /// when none was planned, rates it with reps left and no pain, and completes the workout's exercises.
    private func log(_ workout: Workout, reps: [Int], weightTenthsPounds: Int?, repsLeft: RepsInReserve) {
        if workout.status == .planned { workout.startAndCascade() }
        for exercise in workout.workoutExercises {
            exercise.skipWarmups()
            for (index, set) in exercise.workingSets.enumerated() {
                set.reps = reps[min(index, reps.count - 1)]
                set.weightTenthsPounds = set.weightTenthsPlannedPounds ?? weightTenthsPounds
                set.complete()
            }
            exercise.addFeedback(feedback: ExerciseFeedback(repsInReserve: repsLeft, levelOfPain: .none))
            exercise.completeAndCascade()
        }
    }
}
