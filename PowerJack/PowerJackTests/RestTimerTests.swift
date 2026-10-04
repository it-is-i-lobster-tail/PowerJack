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

    @Test("Fatigue level picks the rest length")
    func fatigueLevelRestLengths() {
        #expect(FatigueLevel.low.restLength == .short)
        #expect(FatigueLevel.moderate.restLength == .standard)
        #expect(FatigueLevel.high.restLength == .long)
        #expect(RestLength.short.defaultDuration == .seconds(75))
        #expect(RestLength.standard.defaultDuration == .seconds(135))
        #expect(RestLength.long.defaultDuration == .seconds(180))
        #expect(RestLength.standard.defaultDuration.minuteSecondText == "2:15")
    }

    @Test("Fatigue levels keep the raw values older stores saved")
    func fatigueLevelRawValues() {
        #expect(FatigueLevel(rawValue: "light") == .low)
        #expect(FatigueLevel(rawValue: "medium") == .moderate)
        #expect(FatigueLevel(rawValue: "heavy") == .high)
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

    @Test("Completing a set rests for its exercise's fatigue level before the next set")
    func restAfterSet() throws {
        let workout = try makeWorkout([(.high, 3)])
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

    @Test("Finishing an exercise's last set starts no rest before the next exercise")
    func noRestBetweenExercises() throws {
        let workout = try makeWorkout([(.low, 1), (.high, 2)])
        workout.workoutExercises[0].workoutSets[0].complete(at: start)

        #expect(workout.currentRest == nil)
        let current = try #require(workout.currentSet)
        #expect(current.workoutExercise === workout.workoutExercises[1])
        #expect(current.workoutSet.order == 0)
    }

    @Test("The Live Activity shows every set, the current one's target, with or without a rest")
    func activityState() throws {
        let workout = try makeWorkout([(.high, 2)])

        let fresh = try #require(workout.activityState(at: start))
        #expect(fresh.exerciseName == "Exercise 1")
        #expect(fresh.setText == "Set 1 of 2")
        #expect(fresh.sets.map(\.progress) == [.current, .upcoming])
        #expect(fresh.sets[0].weightText(repsOnly: false) == "225")
        #expect(fresh.sets[0].repsText == "8")
        #expect(fresh.canCompleteAtTarget)
        #expect(fresh.rest == nil)

        let firstSet = workout.workoutExercises[0].workoutSets[0]
        firstSet.reps = 9
        firstSet.complete(at: start)
        let resting = try #require(workout.activityState(at: start))
        #expect(resting.setOrder == 1)
        #expect(resting.sets.map(\.progress) == [.done, .current])
        // Done sets show what was logged, not the target.
        #expect(resting.sets[0].repsText == "9")
        #expect(resting.rest == start...start.addingTimeInterval(180))
        // Once the rest runs out the set stays up without a timer.
        #expect(workout.activityState(at: start.addingTimeInterval(180))?.rest == nil)

        workout.workoutExercises[0].workoutSets[1].complete(at: start.addingTimeInterval(200))
        #expect(workout.activityState(at: start) == nil)
    }

    @Test("Sets without a target show blanks and can't be checked from the Live Activity")
    func activityStateWithoutTarget() throws {
        let workout = Workout(order: 0)
        let exercise = Exercise(
            exerciseName: "Row",
            exerciseEquipment: .barbell,
            primaryMuscleFocus: .back,
            fatigueLevel: .moderate
        )
        let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
        _ = workoutExercise.addSet()
        container.mainContext.insert(workout)
        workout.startAndCascade()

        let state = try #require(workout.activityState(at: start))
        #expect(state.sets[0].weightText(repsOnly: false) == "–")
        #expect(state.sets[0].repsText == "–")
        #expect(!state.canCompleteAtTarget)
        #expect(!workout.completeCurrentSetAtTarget(exerciseOrder: 0, setOrder: 0))
    }

    @Test("Checking a set from the Live Activity logs exactly its target")
    func completeAtTarget() throws {
        let workout = try makeWorkout([(.moderate, 2)])
        let sets = workout.workoutExercises[0].workoutSets

        // Only the set the activity showed.
        #expect(!workout.completeCurrentSetAtTarget(exerciseOrder: 0, setOrder: 1))

        #expect(workout.completeCurrentSetAtTarget(exerciseOrder: 0, setOrder: 0, at: start))
        #expect(sets[0].status == .complete)
        #expect(sets[0].reps == 8)
        #expect(sets[0].weightTenthsPounds == 2250)
        #expect(sets[0].completedAt == start)

        // Something else typed in the app has to be finished in the app.
        sets[1].reps = 6
        #expect(!sets[1].canCompleteAtTarget(repsOnly: false))
        #expect(!workout.completeCurrentSetAtTarget(exerciseOrder: 0, setOrder: 1))
        #expect(sets[1].status == .active)
    }

    @Test("There is no rest before the first set, after the last set, or outside a running workout")
    func noRest() throws {
        let fresh = try makeWorkout([(.moderate, 2)])
        #expect(fresh.currentRest == nil)

        let done = try makeWorkout([(.moderate, 2)])
        for set in done.workoutExercises[0].workoutSets {
            set.complete(at: start)
        }
        #expect(done.currentRest == nil)

        let planned = try makeWorkout([(.moderate, 2)], started: false)
        planned.workoutExercises[0].workoutSets[0].complete(at: start)
        #expect(planned.workoutExercises[0].workoutSets[0].completedAt == start)
        #expect(planned.currentRest == nil)
    }

    @Test("Reopening the latest set falls back to the rest before it")
    func reopenedSet() throws {
        let workout = try makeWorkout([(.moderate, 3)])
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
        let workout = try makeWorkout([(.moderate, 2)], equipment: .bodyweight)
        workout.workoutExercises[0].workoutSets[0].complete(at: start)

        let rest = try #require(workout.currentRest)
        #expect(rest.weightTenthsPounds == nil)
        #expect(rest.prescriptionText == "8 reps")
    }

    @Test("The rest is restored from the store after a relaunch")
    func restSurvivesRelaunch() throws {
        let workout = try makeWorkout([(.high, 2)])
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
        _ plan: [(fatigueLevel: FatigueLevel, sets: Int)],
        equipment: Equipment = .barbell,
        started: Bool = true
    ) throws -> Workout {
        let workout = Workout(order: 0)
        for (index, entry) in plan.enumerated() {
            let exercise = Exercise(
                exerciseName: "Exercise \(index + 1)",
                exerciseEquipment: equipment,
                primaryMuscleFocus: .chest,
                fatigueLevel: entry.fatigueLevel
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
