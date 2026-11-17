//
//  ModelSharedRulesTests.swift
//  PowerJackTests
//
//  Rules the program-side models share: which statuses are still open, how a workout ends,
//  what a planner's plan holds when it's cleared, and the sets a new exercise starts with.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ModelSharedRulesTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    // MARK: Status

    @Test("Planned and active are open, the rest are finished", arguments: Status.allCases)
    func statusOpenOrFinished(status: Status) {
        let open: Set<Status> = [.planned, .active]
        #expect(status.isOpen == open.contains(status))
        #expect(status.isFinished == !open.contains(status))
    }

    // MARK: Counting sets

    @Test("Set counts include warmups, and a workout adds up its exercises")
    func setCountsIncludeWarmups() throws {
        let workout = Workout(order: 0)
        container.mainContext.insert(workout)
        let bench = try #require(workout.addWorkoutExercise(exercise: makeExercise(name: "Bench")))
        let row = try #require(workout.addWorkoutExercise(exercise: makeExercise(name: "Row")))
        bench.addInitialSets()
        row.addInitialSets()
        workout.startAndCascade()

        let firstWorkingSet = try #require(bench.workingSets.first)
        bench.completeSet(firstWorkingSet)

        // Logging the first working set skips the warmups still to do.
        #expect(bench.setCount(.complete) == 1)
        #expect(bench.setCount(.skipped) == WorkoutExercise.initialWarmupSets)
        #expect(bench.setCount(.active) == WorkoutExercise.initialSets - 1)
        #expect(workout.setCount(.complete) == 1)
        #expect(workout.setCount(.active) == bench.setCount(.active) + row.totalSets)
        #expect(workout.totalSets == bench.totalSets + row.totalSets)
        #expect(bench.hasLoggedSets)
        #expect(!row.hasLoggedSets)
        #expect(workout.hasLoggedSets)
    }

    @Test("Warmups and working sets are counted and numbered apart")
    func setsOfType() throws {
        let workoutExercise = makeWorkoutExercise()
        workoutExercise.addInitialSets()

        #expect(workoutExercise.sets(ofType: .warmup) == workoutExercise.warmupSets)
        #expect(workoutExercise.sets(ofType: .working) == workoutExercise.workingSets)
        let secondWorkingSet = try #require(workoutExercise.workingSets.last)
        #expect(workoutExercise.number(of: secondWorkingSet) == 2)
        #expect(workoutExercise.count(sameTypeAs: secondWorkingSet) == WorkoutExercise.initialSets)
    }

    // MARK: New exercises

    @Test("A new exercise starts with warmups and two working sets, in order")
    func initialSets() {
        let workoutExercise = makeWorkoutExercise()
        workoutExercise.addInitialSets()

        #expect(workoutExercise.warmupSets.count == WorkoutExercise.initialWarmupSets)
        #expect(workoutExercise.workingSets.count == WorkoutExercise.initialSets)
        #expect(workoutExercise.workoutSets.map(\.order) == Array(0..<workoutExercise.totalSets))
        #expect(workoutExercise.workoutSets.allSatisfy { $0.status == .planned })
    }

    @Test("Week 1 of a new program gives every exercise the starting sets")
    func programWeekOneStartingSets() throws {
        let program = try makeProgram(weeks: 2, workouts: 2)
        let exercises = program.programWeeks[0].workouts.flatMap(\.workoutExercises)

        #expect(exercises.count == 2)
        for workoutExercise in exercises {
            #expect(workoutExercise.warmupSets.count == WorkoutExercise.initialWarmupSets)
            #expect(workoutExercise.workingSets.count == WorkoutExercise.initialSets)
        }
        #expect(program.programWeeks[1].workouts.isEmpty)
    }

    @Test("An exercise added to a workout in progress gets the starting sets, ready to log")
    func layoutAddsStartingSets() throws {
        let workout = Workout(order: 0)
        container.mainContext.insert(workout)
        let bench = try #require(workout.addWorkoutExercise(exercise: makeExercise(name: "Bench")))
        bench.addInitialSets()
        workout.startAndCascade()

        let curl = makeExercise(name: "Curl")
        let benchExercise = try #require(bench.exercise)
        let layout = workout.applyLayout([
            (workoutExercise: bench, exercise: benchExercise, supersetID: nil),
            (workoutExercise: nil, exercise: curl, supersetID: nil),
        ])

        let added = try #require(layout.last)
        #expect(added.exercise === curl)
        #expect(added.status == .active)
        #expect(added.warmupSets.count == WorkoutExercise.initialWarmupSets)
        #expect(added.workingSets.count == WorkoutExercise.initialSets)
        #expect(added.workoutSets.allSatisfy { $0.status == .active })
    }

    // MARK: Clearing a plan

    @Test("Clearing a planned progression drops every target and a pending check-in, but keeps the sets")
    func clearPlannedProgression() {
        let workoutExercise = makePlannedExercise()
        workoutExercise.requireCheckIn(sourcePain: .severe)
        let sets = workoutExercise.workoutSets

        workoutExercise.clearPlannedProgression()

        expectNoPlan(on: workoutExercise)
        #expect(workoutExercise.checkIn == .none)
        #expect(workoutExercise.checkInSourcePain == nil)
        #expect(!workoutExercise.locked)
        #expect(workoutExercise.workoutSets == sets)
    }

    @Test("Changing the exercise drops the old exercise's plan and check-in")
    func changeExerciseDropsPlan() {
        let workoutExercise = makePlannedExercise()
        workoutExercise.requireCheckIn(sourcePain: .severe)
        // A held exercise is locked, and only an open one can change.
        workoutExercise.resolveCheckIn(.continue)
        let replacement = makeExercise(name: "Row")

        workoutExercise.changeExercise(newExercise: replacement)

        #expect(workoutExercise.exercise === replacement)
        expectNoPlan(on: workoutExercise)
        #expect(workoutExercise.checkIn == .none)
        #expect(workoutExercise.checkInSourcePain == nil)
        #expect(workoutExercise.warmupSets.count == WorkoutExercise.initialWarmupSets)
        #expect(workoutExercise.workingSets.count == WorkoutExercise.initialSets)
    }

    @Test("Replacing planned sets deletes the old rows and keeps the other type")
    func replacePlannedSets() throws {
        let workoutExercise = makeWorkoutExercise()
        try container.mainContext.save()
        workoutExercise.addInitialSets()
        let warmups = workoutExercise.warmupSets

        workoutExercise.replacePlannedWorkingSets([(reps: 5, weightTenthsPounds: 2250), (reps: 5, weightTenthsPounds: 2250), (reps: 5, weightTenthsPounds: 2250)])
        #expect(workoutExercise.warmupSets == warmups)
        #expect(workoutExercise.workingSets.map(\.repsPlanned) == [5, 5, 5])

        workoutExercise.replacePlannedWarmups([(reps: 10, weightTenthsPounds: 1350)])
        #expect(workoutExercise.warmupSets.map(\.repsPlanned) == [10])
        #expect(workoutExercise.workingSets.count == 3)
        #expect(workoutExercise.workoutSets.map(\.order) == Array(0..<4))

        try container.mainContext.save()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<WorkoutSet>()) == 4)
    }

    // MARK: Ending

    @Test("Ending a workout stamps the end and ends a pause still going", arguments: [Status.complete, .stopped, .skipped])
    func workoutEndEndsPause(as status: Status) {
        let workout = Workout(order: 0)
        container.mainContext.insert(workout)
        workout.start(at: .now.addingTimeInterval(-600))
        workout.pause(at: .now.addingTimeInterval(-60))

        switch status {
        case .complete: workout.complete()
        case .stopped: workout.stop()
        default: workout.skip()
        }

        #expect(workout.status == status)
        #expect(workout.locked)
        #expect(!workout.isPaused)
        #expect(workout.pausedSeconds >= 60)
        #expect(workout.endedAt != nil)
        #expect(workout.isFinished)
    }

    @Test("A week ends once, whichever way it ends")
    func weekEndsOnce() {
        let week = ProgramWeek(order: 0)
        week.start()
        week.skip()
        week.complete()
        week.stop()
        #expect(week.status == .skipped)
        #expect(week.locked)
    }

    @Test("Stopped workouts don't count as finished in a program's progress")
    func programProgressLeavesOutStopped() throws {
        let program = try makeProgram(weeks: 1, workouts: 3)
        program.start()
        let workouts = program.programWeeks[0].workouts
        program.skipWorkout(workouts[0])
        workouts[1].start()
        workouts[1].stop()

        #expect(workouts[1].isFinished)
        #expect(program.workoutsFinished == 1)
        #expect(program.percentFinished == 33)
    }

    @Test("A program knows whether and when a set was last logged")
    func programLoggedSets() throws {
        let program = try makeProgram(weeks: 2, workouts: 2)
        program.start()
        #expect(!program.hasLoggedSets)
        #expect(program.lastLoggedAt == nil)

        let workout = try #require(program.nextWorkout)
        workout.startAndCascade()
        let workoutExercise = try #require(workout.workoutExercises.first)
        let set = try #require(workoutExercise.workingSets.first)
        let loggedAt = Date.now
        workoutExercise.completeSet(set, at: loggedAt)

        #expect(program.hasLoggedSets)
        #expect(program.lastLoggedAt == loggedAt)
    }

    // MARK: Helpers

    private func expectNoPlan(on workoutExercise: WorkoutExercise, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(workoutExercise.rirTarget == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.progressionCode == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.progressionNote == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.strengthRole == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.targetReps == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.repOffset == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.intendedLoadKg == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.powerJackRoleValue == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.powerJackTagValue == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.powerJackTopSetsValue == 0, sourceLocation: sourceLocation)
        #expect(workoutExercise.powerJackTopRIRValue == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.powerJackLoadTargetValue == nil, sourceLocation: sourceLocation)
        #expect(workoutExercise.powerJackTopLoadTargetValue == nil, sourceLocation: sourceLocation)
        #expect(!workoutExercise.powerJackCalibratingValue, sourceLocation: sourceLocation)
    }

    /// A planned exercise holding every kind of target a planner writes.
    private func makePlannedExercise() -> WorkoutExercise {
        let workoutExercise = makeWorkoutExercise()
        workoutExercise.addInitialSets()
        workoutExercise.setProgression(rirTarget: 2, code: "test", note: "+5 lb")
        workoutExercise.setStrengthTargets(role: .primary, reps: 5, repOffset: 1, intendedLoadKg: 100, topSets: 1)
        workoutExercise.powerJackRoleValue = "heavy"
        workoutExercise.powerJackTagValue = "M"
        workoutExercise.powerJackTopRIRValue = 2
        workoutExercise.powerJackLoadTargetValue = 100
        workoutExercise.powerJackTopLoadTargetValue = 110
        workoutExercise.powerJackCalibratingValue = true
        #expect(workoutExercise.rirTarget == 2)
        #expect(workoutExercise.strengthRole == .primary)
        #expect(workoutExercise.powerJackTopSetsValue == 1)
        return workoutExercise
    }

    private func makeExercise(name: String) -> Exercise {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        container.mainContext.insert(exercise)
        return exercise
    }

    private func makeWorkoutExercise() -> WorkoutExercise {
        let workoutExercise = WorkoutExercise(exercise: makeExercise(name: "Bench"), order: 0)
        container.mainContext.insert(workoutExercise)
        return workoutExercise
    }

    private func makeProgram(weeks: Int, workouts: Int) throws -> Program {
        let exercise = makeExercise(name: "Bench")
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: workouts, templateMuscleFocus: [.chest])
        for _ in 0..<workouts {
            template.addTemplateWorkout().addTemplateExercise(exercise: exercise)
        }
        container.mainContext.insert(template)
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try container.mainContext.insertAndSave(program)
        return program
    }
}
