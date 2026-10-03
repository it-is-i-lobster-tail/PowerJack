//
//  RestTimerTests.swift
//  PowerJackTests
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct RestTimerTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("Fatigue sets the rest between sets")
    func fatigueRestDurations() {
        #expect(Fatigue.light.restDuration == .seconds(75))
        #expect(Fatigue.medium.restDuration == .seconds(135))
        #expect(Fatigue.heavy.restDuration == .seconds(180))
        #expect(Fatigue.medium.restDuration.minuteSecondText == "2:15")
    }

    @Test("Sets record when they were completed and forget it when reopened")
    func completedAtLifecycle() {
        let set = WorkoutSet(order: 0, plannedReps: 8, plannedWeightTenthsPounds: nil)
        set.start()
        #expect(set.completedAt == nil)

        set.complete(at: start)
        #expect(set.completedAt == start)

        // Finishing the workout later keeps the real completion time.
        set.completeAndLock(at: start.addingTimeInterval(600))
        #expect(set.completedAt == start)

        let unlogged = WorkoutSet(order: 1, plannedReps: 8, plannedWeightTenthsPounds: nil)
        unlogged.start()
        unlogged.completeAndLock(at: start.addingTimeInterval(600))
        #expect(unlogged.completedAt == start.addingTimeInterval(600))

        let reopened = WorkoutSet(order: 2, plannedReps: 8, plannedWeightTenthsPounds: nil)
        reopened.start()
        reopened.complete(at: start)
        reopened.start()
        #expect(reopened.status == .active)
        #expect(reopened.completedAt == nil)
    }

    @Test("Completing a set rests for its exercise's fatigue before the next set")
    func restAfterSet() throws {
        let workout = try makeWorkout([(.heavy, 3)])
        let sets = workout.workoutExercises[0].workoutSets

        sets[0].complete(at: start)

        let rest = try #require(workout.currentRest)
        #expect(rest.startedAt == start)
        #expect(rest.endsAt == start.addingTimeInterval(180))
        #expect(rest.exerciseName == "Exercise 1")
        #expect(rest.setNumber == 2)
        #expect(rest.setCount == 3)
        #expect(rest.reps == 8)
        #expect(rest.weightTenthsPounds == 2250)
    }

    @Test("Moving to another exercise rests for the longer of the two")
    func restBetweenExercises() throws {
        let lightThenHeavy = try makeWorkout([(.light, 1), (.heavy, 2)])
        lightThenHeavy.workoutExercises[0].workoutSets[0].complete(at: start)
        let intoHeavy = try #require(lightThenHeavy.currentRest)
        #expect(intoHeavy.exerciseName == "Exercise 2")
        #expect(intoHeavy.setNumber == 1)
        #expect(intoHeavy.duration == 180)

        let heavyThenLight = try makeWorkout([(.heavy, 1), (.light, 2)])
        heavyThenLight.workoutExercises[0].workoutSets[0].complete(at: start)
        #expect(heavyThenLight.currentRest?.duration == 180)

        let lightOnly = try makeWorkout([(.light, 2)])
        lightOnly.workoutExercises[0].workoutSets[0].complete(at: start)
        #expect(lightOnly.currentRest?.duration == 75)
    }

    @Test("There is no rest before the first set, after the last set, or outside a running workout")
    func noRest() throws {
        let fresh = try makeWorkout([(.medium, 2)])
        #expect(fresh.currentRest == nil)

        let done = try makeWorkout([(.medium, 2)])
        for set in done.workoutExercises[0].workoutSets {
            set.complete(at: start)
        }
        #expect(done.currentRest == nil)

        let planned = try makeWorkout([(.medium, 2)], started: false)
        planned.workoutExercises[0].workoutSets[0].complete(at: start)
        #expect(planned.workoutExercises[0].workoutSets[0].completedAt == start)
        #expect(planned.currentRest == nil)
    }

    @Test("Reopening the latest set falls back to the rest before it")
    func reopenedSet() throws {
        let workout = try makeWorkout([(.medium, 3)])
        let sets = workout.workoutExercises[0].workoutSets
        sets[0].complete(at: start)
        sets[1].complete(at: start.addingTimeInterval(200))
        #expect(workout.currentRest?.startedAt == start.addingTimeInterval(200))
        #expect(workout.currentRest?.setNumber == 3)

        sets[1].start()

        let rest = try #require(workout.currentRest)
        #expect(rest.startedAt == start)
        #expect(rest.setNumber == 2)
    }

    @Test("Bodyweight sets never show a weight")
    func bodyweightRest() throws {
        let workout = try makeWorkout([(.medium, 2)], equipment: .bodyweight)
        workout.workoutExercises[0].workoutSets[0].complete(at: start)

        let rest = try #require(workout.currentRest)
        #expect(rest.weightTenthsPounds == nil)
        #expect(rest.prescriptionText == "8 reps")
    }

    @Test("The rest is restored from the store after a relaunch")
    func restSurvivesRelaunch() throws {
        let workout = try makeWorkout([(.heavy, 2)])
        workout.workoutExercises[0].workoutSets[0].complete(at: start)
        try container.mainContext.save()

        // A fresh context stands in for a relaunch.
        let reloaded = try #require(try ModelContext(container).fetch(FetchDescriptor<Workout>()).first)
        #expect(reloaded.currentRest != nil)
        #expect(reloaded.currentRest == workout.currentRest)
    }

    @Test("The seeded active workout is resting before its last pulldown set")
    func seededRest() throws {
        let scenario = PowerJackSeed.weekOneProgress()
        let rest = try #require(scenario.weekOneWorkouts[1].currentRest)
        #expect(rest.exerciseName == "Lat Pulldown")
        #expect(rest.setNumber == 3)
        #expect(rest.duration == 135)
    }

    @Test("A rest counts down, then offers the next set until its window runs out")
    func restWindows() {
        let rest = RestPeriod(
            startedAt: start,
            endsAt: start.addingTimeInterval(135),
            exerciseName: "Row",
            setNumber: 2,
            setCount: 3,
            reps: 8,
            weightTenthsPounds: 2250
        )

        #expect(rest.isResting(at: start.addingTimeInterval(134)))
        #expect(!rest.isResting(at: start.addingTimeInterval(135)))
        #expect(rest.fractionRemaining(at: start) == 1)
        #expect(rest.fractionRemaining(at: start.addingTimeInterval(135)) == 0)
        #expect(!rest.isExpired(at: rest.endsAt.addingTimeInterval(RestPeriod.readyWindow - 1)))
        #expect(rest.isExpired(at: rest.endsAt.addingTimeInterval(RestPeriod.readyWindow)))
        #expect(rest.detailText == "Set 2 of 3 · 8 reps × 225 lb")

        var openEnded = rest
        openEnded.reps = nil
        #expect(openEnded.prescriptionText == "2 RIR × 225 lb")
        openEnded.weightTenthsPounds = nil
        #expect(openEnded.prescriptionText == "2 RIR")
    }

    @Test("Opening the current exercise shows the session and asks it to scroll")
    func openCurrentExercise() {
        let scenario = PowerJackSeed.weekOneProgress()
        let router = ProgramsRouter()

        router.showCurrentExercise(of: scenario.program)
        #expect(router.path == [.detail(scenario.program), .session(scenario.program)])
        #expect(router.currentExerciseRequest == 1)

        router.showCurrentExercise(of: scenario.program)
        #expect(router.path.count == 2)
        #expect(router.currentExerciseRequest == 2)
    }

    // MARK: Helpers

    /// Builds a workout of 8 rep × 225 lb sets, one exercise per entry.
    private func makeWorkout(
        _ plan: [(fatigue: Fatigue, sets: Int)],
        equipment: Equipment = .barbell,
        started: Bool = true
    ) throws -> Workout {
        let workout = Workout(order: 0)
        for (index, entry) in plan.enumerated() {
            let exercise = Exercise(
                exerciseName: "Exercise \(index + 1)",
                exerciseEquipment: equipment,
                primaryMuscleFocus: .chest,
                fatigue: entry.fatigue
            )
            let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
            for _ in 0..<entry.sets {
                _ = workoutExercise.addSet(plannedReps: 8, plannedWeightTenthsPounds: 2250)
            }
        }
        container.mainContext.insert(workout)
        if started {
            workout.startAndCascade()
        }
        return workout
    }
}
