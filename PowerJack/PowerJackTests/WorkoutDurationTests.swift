//
//  WorkoutDurationTests.swift
//  PowerJackTests
//
//  How long a workout, each exercise, and each set took.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WorkoutDurationTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("The workout runs from Start Workout until it's finished")
    func workoutDuration() throws {
        let workout = try makeWorkout()
        #expect(workout.duration() == nil)

        workout.startAndCascade(at: start)
        #expect(workout.startedAt == start)
        #expect(workout.duration(at: start + 90) == 90)

        workout.skipRemainingSets()
        workout.completeAndCascade()
        let endedAt = try #require(workout.endedAt)
        // Once finished, the clock stops.
        #expect(workout.duration(at: endedAt + 600) == endedAt.timeIntervalSince(start))
    }

    @Test("Each set runs from the set logged before it, and the first from the workout's start")
    func setDurations() throws {
        let workout = try makeWorkout()
        workout.startAndCascade(at: start)
        let bench = workout.workoutExercises[0]
        let (first, second) = (bench.workingSets[0], bench.workingSets[1])

        bench.completeSet(first, at: start + 120)
        bench.completeSet(second, at: start + 300)

        #expect(first.startedAt == start)
        #expect(first.duration == 120)
        #expect(second.duration == 180)
        #expect(bench.duration == 300)
    }

    @Test("Back-to-back exercises split the time, so they add up to the workout")
    func interleavedSets() throws {
        let workout = try makeWorkout()
        workout.startAndCascade(at: start)
        let (bench, row) = (workout.workoutExercises[0], workout.workoutExercises[1])

        // A1, B1, A2, B2, as in a superset.
        bench.completeSet(bench.workingSets[0], at: start + 60)
        row.completeSet(row.workingSets[0], at: start + 100)
        bench.completeSet(bench.workingSets[1], at: start + 250)
        row.completeSet(row.workingSets[1], at: start + 300)

        #expect(bench.workingSets.map(\.duration) == [60, 150])
        #expect(row.workingSets.map(\.duration) == [40, 50])
        #expect(bench.duration == 210)
        #expect(row.duration == 90)
        #expect((bench.duration ?? 0) + (row.duration ?? 0) == workout.duration(at: start + 300))
    }

    @Test("Reopening a set clears its time until it's logged again")
    func reopenedSetLosesTime() throws {
        let workout = try makeWorkout()
        workout.startAndCascade(at: start)
        let bench = workout.workoutExercises[0]
        let set = bench.workingSets[0]
        bench.completeSet(set, at: start + 60)

        set.start()
        #expect(set.startedAt == nil)
        #expect(set.duration == nil)
        #expect(bench.duration == nil)

        bench.completeSet(set, at: start + 90)
        #expect(set.duration == 90)
    }

    @Test("Skipped sets and workouts started before timing have no set time")
    func untimedSets() throws {
        let workout = try makeWorkout()
        workout.startAndCascade(at: start)
        let bench = workout.workoutExercises[0]
        bench.workingSets[0].skip()
        #expect(bench.workingSets[0].duration == nil)

        // A set completed without its workout, as in workouts logged before this update.
        bench.workingSets[1].complete(at: start + 60)
        #expect(bench.workingSets[1].duration == nil)
        #expect(bench.duration == nil)
    }

    @Test("Elapsed time reads as minutes and seconds, with hours past an hour")
    func elapsedText() {
        #expect(TimeInterval(75).elapsedText == "1:15")
        #expect(TimeInterval(3725).elapsedText == "1:02:05")
    }

    private func makeWorkout() throws -> Workout {
        let context = container.mainContext
        let exercises = [("Bench", Muscle.chest), ("Row", Muscle.back)].map { name, muscle in
            Exercise(
                exerciseName: name,
                exerciseEquipment: .barbell,
                primaryMuscleFocus: muscle,
                minReps: 6,
                maxReps: 12
            )
        }
        exercises.forEach(context.insert)
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        let templateWorkout = template.addTemplateWorkout()
        for exercise in exercises { _ = templateWorkout.addTemplateExercise(exercise: exercise) }
        context.insert(template)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        return try #require(program.nextWorkout)
    }
}
