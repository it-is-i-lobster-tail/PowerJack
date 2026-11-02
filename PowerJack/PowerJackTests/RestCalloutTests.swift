//
//  RestCalloutTests.swift
//  PowerJackTests
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct RestCalloutTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("The callout says the weight only when it changes, then just the reps")
    func weightOnlyWhenItChanges() throws {
        try WeightUnit.$pinned.withValue(.pounds) {
            let (workout, sets) = try makeWorkout(equipment: .barbell, sets: [(5, 1350), (10, 2250), (7, 2250), (7, 2250)])
            #expect(workout.restCallout == nil)

            sets[0].completeAtTarget(repsOnly: false, at: start)
            let first = try #require(workout.restCallout)
            #expect(first.text == "Start set. 225 pounds, 10 reps.")
            #expect(first.endsAt == workout.currentRest?.endsAt)

            sets[1].completeAtTarget(repsOnly: false, at: start.addingTimeInterval(200))
            #expect(workout.restCallout?.text == "Start set. 7 reps.")

            // A weight typed in differently from the plan counts as the last weight.
            sets[2].weightTenthsPounds = 2300
            sets[2].reps = 7
            sets[2].complete(at: start.addingTimeInterval(400))
            #expect(workout.restCallout?.text == "Start set. 225 pounds, 7 reps.")
        }
    }

    @Test("Kilos, halves, one rep, open-ended reps and bodyweight each say only what's needed")
    func spokenLoads() throws {
        #expect(RestCallout.text(weightTenthsPounds: 2260, reps: 5, unit: .kilograms) == "Start set. 102.5 kilos, 5 reps.")
        #expect(RestCallout.text(weightTenthsPounds: 12250, reps: 1, unit: .pounds) == "Start set. 1225 pounds, 1 rep.")
        #expect(RestCallout.text(weightTenthsPounds: 2250, reps: nil, unit: .pounds) == "Start set. 225 pounds.")
        #expect(RestCallout.text(weightTenthsPounds: nil, reps: nil, unit: .pounds) == "Start set.")
        #expect(RestCallout.sample(in: .pounds) == "Start set. 225 pounds, 10 reps.")
        #expect(RestCallout.sample(in: .kilograms) == "Start set. 100 kilos, 10 reps.")

        let (workout, sets) = try makeWorkout(equipment: .bodyweight, sets: [(12, nil), (12, nil)])
        sets[0].completeAtTarget(repsOnly: true, at: start)
        #expect(workout.restCallout?.text == "Start set. 12 reps.")
    }

    @Test("A superset only says to start the next round")
    func superset() throws {
        let workout = Workout(order: 0)
        let supersetID = UUID()
        for name in ["A", "B"] {
            let exercise = Exercise(exerciseName: name, exerciseEquipment: .dumbbell, primaryMuscleFocus: .biceps, fatigueLevel: .low)
            let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
            workoutExercise.setSuperset(supersetID)
            for _ in 0..<2 {
                _ = workoutExercise.addSet(plannedReps: 10, plannedWeightTenthsPounds: 300)
            }
        }
        container.mainContext.insert(workout)
        workout.startAndCascade()

        workout.workoutExercises[0].workoutSets[0].complete(at: start)
        // Halfway through a round there's no rest, so nothing to say.
        #expect(workout.restCallout == nil)

        workout.workoutExercises[1].workoutSets[0].complete(at: start.addingTimeInterval(60))
        #expect(workout.restCallout?.text == "Start superset.")
    }

    private func makeWorkout(
        equipment: Equipment,
        sets: [(reps: Int, weightTenthsPounds: Int?)]
    ) throws -> (Workout, [WorkoutSet]) {
        let workout = Workout(order: 0)
        let exercise = Exercise(exerciseName: "Squat", exerciseEquipment: equipment, primaryMuscleFocus: .quads, fatigueLevel: .high)
        let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
        for set in sets {
            _ = workoutExercise.addSet(plannedReps: set.reps, plannedWeightTenthsPounds: set.weightTenthsPounds)
        }
        container.mainContext.insert(workout)
        workout.startAndCascade()
        return (workout, workoutExercise.workoutSets)
    }
}
