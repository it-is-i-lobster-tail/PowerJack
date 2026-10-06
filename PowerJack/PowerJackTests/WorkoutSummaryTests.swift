//
//  WorkoutSummaryTests.swift
//  PowerJackTests
//

import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WorkoutSummaryTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("Completed sets are totaled per primary muscle, most first, without empty muscles")
    func setsByMuscle() {
        let exercises = PowerJackSeed.makeExercises()
        // Bench (chest), Squat (quads), Pull Up (back), Lat Pulldown (back).
        let workout = PowerJackSeed.makeWorkout(
            order: 0,
            exercises: Array(exercises[0...3]),
            sets: [
                sets([.complete, .complete]),
                sets([.skipped, .skipped]),
                sets([.complete, .complete]),
                sets([.complete, .skipped]),
            ]
        )
        container.mainContext.insert(workout)

        #expect(workout.completedSetsByMuscle == [
            MuscleSetCount(muscle: .back, sets: 3),
            MuscleSetCount(muscle: .chest, sets: 2),
        ])
    }

    @Test("A workout with nothing completed has no summary rows")
    func nothingCompleted() {
        let exercises = PowerJackSeed.makeExercises()
        let workout = PowerJackSeed.makeWorkout(
            order: 0,
            exercises: [exercises[0]],
            sets: [sets([.skipped, .skipped])]
        )
        container.mainContext.insert(workout)

        #expect(workout.completedSetsByMuscle.isEmpty)
    }

    private func sets(_ statuses: [Status]) -> [PowerJackSeed.SeedSet] {
        statuses.map {
            PowerJackSeed.SeedSet(
                plannedReps: 8,
                plannedWeightTenthsPounds: 1000,
                actualReps: 8,
                actualWeightTenthsPounds: 1000,
                status: $0
            )
        }
    }
}
