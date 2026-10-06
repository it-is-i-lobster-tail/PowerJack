//
//  VolumeTests.swift
//  PowerJackTests
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct VolumeTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()
    private let day: TimeInterval = 24 * 60 * 60

    @Test("Each completed working set counts 1 for the primary muscle and 0.5 for each secondary")
    func loggedSetsCountSecondaryMusclesAsHalf() {
        let exercises = PowerJackSeed.makeExercises()
        // Bench (chest; triceps, shoulders) and Pull Up (back; biceps, forearms).
        let workout = PowerJackSeed.makeWorkout(
            order: 0,
            exercises: [exercises[0], exercises[2]],
            sets: [
                sets([.complete, .complete, .complete]),
                sets([.complete, .complete, .skipped]),
            ]
        )
        container.mainContext.insert(workout)

        #expect(workout.loggedSetsByMuscle == [
            .chest: 3, .triceps: 1.5, .shoulders: 1.5,
            .back: 2, .biceps: 1, .forearms: 1,
        ])
    }

    @Test("A log reads back the sets it was given and zero for every other muscle")
    func logColumns() {
        let log = WorkoutLog(date: .now, setsByMuscle: [.chest: 3, .hamstrings: 1.5])

        #expect(log.sets(for: .chest) == 3)
        #expect(log.sets(for: .hamstrings) == 1.5)
        #expect(log.sets(for: .back) == 0)
    }

    @Test("Averages divide by the weeks since the first workout when that's inside the range")
    func averagesForNewUser() {
        let now = Date.now
        let logs = [
            WorkoutLog(date: now.addingTimeInterval(-14 * day), setsByMuscle: [.chest: 10]),
            WorkoutLog(date: now.addingTimeInterval(-7 * day), setsByMuscle: [.chest: 10]),
        ]

        let averages = WeeklyVolume.averages(of: logs, in: .days90, now: now)

        #expect(averages[.chest] == 10)
        #expect(averages[.back] == 0)
    }

    @Test("Workouts before the range are left out")
    func rangeExcludesOlderLogs() {
        let now = Date.now
        let logs = [
            WorkoutLog(date: now.addingTimeInterval(-60 * day), setsByMuscle: [.chest: 100]),
            WorkoutLog(date: now.addingTimeInterval(-3 * day), setsByMuscle: [.chest: 30]),
        ]

        let averages = WeeklyVolume.averages(of: logs, in: .days30, now: now)
        let weeks = 30.0 / 7.0

        #expect(abs((averages[.chest] ?? 0) - 30 / weeks) < 0.001)
    }

    @Test("Less than a week of history still counts as one week")
    func atLeastOneWeek() {
        let now = Date.now
        let logs = [WorkoutLog(date: now.addingTimeInterval(-1 * day), setsByMuscle: [.quads: 6])]

        #expect(WeeklyVolume.averages(of: logs, in: .all, now: now)[.quads] == 6)
    }

    @Test("No history has no averages")
    func emptyHistory() {
        #expect(WeeklyVolume.averages(of: [], in: .all).isEmpty)
    }

    @Test("Tiers follow the rounded weekly set count", arguments: [
        (0.0, VolumeTier.tooLittle), (2.4, .tooLittle), (2.5, .maintenance), (5.0, .maintenance),
        (6.0, .growth), (12.4, .growth), (13.0, .maxGrowth), (25.0, .maxGrowth), (26.0, .tooMuch),
    ])
    func tiers(weeklySets: Double, tier: VolumeTier) {
        #expect(VolumeTier(weeklySets: weeklySets) == tier)
    }

    @Test("Finishing a workout writes a log that survives deleting its program")
    func logOutlivesProgram() throws {
        let scenario = PowerJackSeed.weekOneProgress()
        let context = scenario.container.mainContext
        let program = scenario.program
        let workout = try #require(program.nextWorkout)
        if workout.status == .planned {
            workout.startAndCascade()
        }
        for workoutExercise in workout.workoutExercises {
            for workoutSet in workoutExercise.workingSets where workoutSet.status == .active {
                workoutSet.reps = 8
                workoutSet.complete()
            }
        }
        let expected = workout.loggedSetsByMuscle

        program.finishWorkout(workout)
        try context.save()
        program.stop()
        program.stopAndCascade()
        program.delete()
        try context.save()

        let logs = try context.fetch(FetchDescriptor<WorkoutLog>())
        #expect(logs.count == 1)
        for (muscle, sets) in expected {
            #expect(logs.first?.sets(for: muscle) == sets)
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
