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

    @Test("Completed sets count 1 for the primary muscle and 0.5 per secondary, most first, without empty muscles")
    func setsByMuscle() {
        let exercises = PowerJackSeed.makeExercises()
        // Bench (chest; triceps, shoulders), Squat (quads; glutes, hamstrings),
        // Pull Up (back; biceps, forearms), Lat Pulldown (back; biceps).
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
            MuscleSetCount(muscle: .biceps, sets: 1.5),
            // Ties keep the catalog's muscle order.
            MuscleSetCount(muscle: .shoulders, sets: 1),
            MuscleSetCount(muscle: .triceps, sets: 1),
            MuscleSetCount(muscle: .forearms, sets: 1),
        ])
    }

    @Test("Two sets each of pull ups, rows and hammer curls give biceps 4 sets")
    func pullsRowsAndCurls() throws {
        let workout = PowerJackSeed.makeWorkout(
            order: 0,
            exercises: try catalogExercises("pull-up", "seated-cable-row", "dumbbell-hammer-curl"),
            sets: [
                sets([.complete, .complete]),
                sets([.complete, .complete]),
                sets([.complete, .complete]),
            ]
        )
        container.mainContext.insert(workout)

        // Biceps: 2 from hammer curls plus four half sets from pull ups and rows.
        #expect(workout.completedSetsByMuscle == [
            MuscleSetCount(muscle: .back, sets: 4),
            MuscleSetCount(muscle: .biceps, sets: 4),
            MuscleSetCount(muscle: .forearms, sets: 3),
            MuscleSetCount(muscle: .abs, sets: 1),
        ])
    }

    @Test("A muscle can end on a half set")
    func halfSets() throws {
        let workout = PowerJackSeed.makeWorkout(
            order: 0,
            exercises: try catalogExercises("pull-up", "dumbbell-hammer-curl"),
            sets: [
                sets([.complete, .complete, .complete]),
                sets([.complete, .complete]),
            ]
        )
        container.mainContext.insert(workout)

        #expect(workout.completedSetsByMuscle == [
            MuscleSetCount(muscle: .biceps, sets: 3.5),
            MuscleSetCount(muscle: .back, sets: 3),
            MuscleSetCount(muscle: .forearms, sets: 2.5),
            MuscleSetCount(muscle: .abs, sets: 1.5),
        ])
    }

    @Test("The summary matches the Volume tab's count")
    func matchesVolume() throws {
        let workout = PowerJackSeed.makeWorkout(
            order: 0,
            exercises: try catalogExercises("barbell-bench-press", "barbell-row", "dumbbell-hammer-curl"),
            sets: [
                sets([.complete, .complete, .skipped]),
                sets([.complete]),
                sets([.complete, .complete, .complete]),
            ]
        )
        container.mainContext.insert(workout)

        let summary = Dictionary(uniqueKeysWithValues: workout.completedSetsByMuscle.map { ($0.muscle, $0.sets) })
        #expect(summary == workout.loggedSetsByMuscle)
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

    private func catalogExercises(_ ids: String...) throws -> [Exercise] {
        try ids.map { id in
            try #require(ExerciseCatalog.entries.first { $0.id == id }).makeExercise()
        }
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
