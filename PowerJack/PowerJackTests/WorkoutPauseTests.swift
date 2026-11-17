//
//  WorkoutPauseTests.swift
//  PowerJackTests
//
//  Pausing a workout from the program's More menu: paused time counts toward neither the
//  workout's time nor the set's, and logging a set or finishing the workout ends the pause.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WorkoutPauseTests {
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("Paused time is left out of the workout's time, which stands still while paused")
    func durationExcludesPause() throws {
        let workout = try makeWorkout()
        workout.startAndCascade(at: start)

        workout.pause(at: start + 60)
        #expect(workout.isPaused)
        #expect(workout.duration(at: start + 60) == 60)
        #expect(workout.duration(at: start + 300) == 60)

        workout.resume(at: start + 360)
        #expect(!workout.isPaused)
        #expect(workout.pausedSeconds == 300)
        #expect(workout.duration(at: start + 420) == 120)
    }

    @Test("Logging a set resumes the workout, and the pause is left out of that set's time")
    func loggingASetResumes() throws {
        let workout = try makeWorkout()
        workout.startAndCascade(at: start)
        let bench = workout.workoutExercises[0]
        let (first, second, third) = (bench.workingSets[0], bench.workingSets[1], bench.workingSets[2])

        bench.completeSet(first, at: start + 100)
        workout.pause(at: start + 150)
        bench.completeSet(second, at: start + 650)

        #expect(!workout.isPaused)
        #expect(workout.pausedSeconds == 500)
        #expect(second.duration == 50)

        // Paused again and resumed from the menu: both pauses add up, and the next set leaves them out too.
        workout.pause(at: start + 700)
        workout.resume(at: start + 800)
        workout.pause(at: start + 850)
        bench.completeSet(third, at: start + 1_000)
        #expect(workout.pausedSeconds == 750)
        #expect(third.duration == 100)
        #expect(bench.duration == workout.duration(at: start + 1_000))
    }

    @Test("A set logged on the watch or from the Live Activity resumes the workout too")
    func otherDevicesResume() throws {
        let workout = try makeWorkout()
        workout.startAndCascade(at: start)
        let bench = workout.workoutExercises[0]

        // How the iPhone applies a set logged on the watch.
        workout.pause(at: start + 60)
        bench.log(weightTenthsPounds: 1_350, reps: 8, on: bench.workingSets[0], at: start + 200, device: SyncDevice.watch)
        #expect(!workout.isPaused)
        #expect(workout.pausedSeconds == 140)
        #expect(bench.workingSets[0].duration == 60)

        // The Live Activity's check button, which logs what's entered.
        bench.workingSets[1].reps = 8
        bench.workingSets[1].weightTenthsPounds = 1_350
        workout.pause(at: start + 260)
        #expect(workout.completeCurrentSet(exerciseOrder: 0, setOrder: bench.workingSets[1].order, at: start + 400))
        #expect(!workout.isPaused)
        #expect(workout.pausedSeconds == 280)
        #expect(bench.workingSets[1].duration == 60)
    }

    @Test("A set logged before the pause began leaves it paused")
    func earlierSetKeepsPause() throws {
        let workout = try makeWorkout()
        workout.startAndCascade(at: start)
        let bench = workout.workoutExercises[0]

        workout.pause(at: start + 300)
        // Logged on the watch at +200, reaching the iPhone after the pause.
        bench.completeSet(bench.workingSets[0], at: start + 200)
        #expect(workout.isPaused)
        #expect(bench.workingSets[0].duration == 200)
    }

    @Test("Finishing a paused workout ends the pause, and its time stays what it was when paused")
    func finishWhilePaused() throws {
        let workout = try makeWorkout()
        let startedAt = Date.now - 600
        workout.startAndCascade(at: startedAt)
        workout.pause(at: startedAt + 300)

        workout.skipRemainingSets()
        workout.completeAndCascade()

        #expect(!workout.isPaused)
        let duration = try #require(workout.duration())
        #expect(abs(duration - 300) < 5)
        #expect(workout.duration(at: .now + 600) == duration)
    }

    @Test("Only a workout in progress pauses")
    func pauseNeedsWorkoutInProgress() throws {
        let workout = try makeWorkout()
        workout.pause(at: start)
        #expect(!workout.isPaused)

        workout.startAndCascade(at: start)
        workout.skipRemainingSets()
        workout.completeAndCascade()
        workout.pause()
        #expect(!workout.isPaused)
        #expect(workout.pausedSeconds == 0)

        // Resuming a workout that isn't paused changes nothing.
        workout.resume()
        #expect(workout.pausedSeconds == 0)
    }

    private func makeWorkout() throws -> Workout {
        let context = container.mainContext
        let bench = Exercise(
            exerciseName: "Bench",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .chest,
            minReps: 6,
            maxReps: 12
        )
        context.insert(bench)
        let template = TemplateProgram(templateName: "Test", workoutsPerWeek: 1, templateMuscleFocus: [.chest])
        _ = template.addTemplateWorkout().addTemplateExercise(exercise: bench)
        context.insert(template)
        let program = Program(programLengthWeeks: 1, templateProgram: template)
        try context.insertAndSave(program)
        program.start()
        let workout = try #require(program.nextWorkout)
        let exercise = try #require(workout.workoutExercises.first)
        while exercise.workingSets.count < 3 { _ = exercise.addSet() }
        return workout
    }
}
