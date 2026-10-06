//
//  BodyweightSetTests.swift
//  PowerJackTests
//
//  Bodyweight sets log reps only: the weight box says "BW" and takes no input.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct BodyweightSetTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("A bodyweight set shows BW, takes no weight, and completes with reps alone")
    func bodyweightSet() async throws {
        let workoutSet = try makeActiveSet(equipment: .bodyweight)
        let screen = try await HostedView(SetHost(workoutSet: workoutSet, repsOnly: true).modelContainer(container))
        defer { screen.close() }

        #expect(screen.contains("Set 1 weight"), "\(screen.labels)")
        #expect(await screen.type("50", into: "Set 1 weight") == false)
        #expect(workoutSet.weightTenthsPounds == nil)

        #expect(await screen.type("12", into: "Set 1 reps"))
        await screen.tap("Set 1 complete")
        #expect(workoutSet.status == .complete)
        #expect(workoutSet.reps == 12)
        #expect(workoutSet.weightTenthsPounds == nil)
    }

    @Test("A loaded set still takes a weight")
    func loadedSet() async throws {
        let workoutSet = try makeActiveSet(equipment: .barbell)
        let screen = try await HostedView(SetHost(workoutSet: workoutSet, repsOnly: false).modelContainer(container))
        defer { screen.close() }

        #expect(await screen.type("135", into: "Set 1 weight"))
        #expect(workoutSet.weightTenthsPounds == 1350)
    }

    private func makeActiveSet(equipment: Equipment) throws -> WorkoutSet {
        let workout = Workout(order: 0)
        let exercise = Exercise(exerciseName: "Test", exerciseEquipment: equipment, primaryMuscleFocus: .chest)
        let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
        let workoutSet = try #require(workoutExercise.addSet(plannedReps: 10, plannedWeightTenthsPounds: nil))
        container.mainContext.insert(workout)
        workout.startAndCascade()
        return workoutSet
    }
}

private struct SetHost: View {
    let workoutSet: WorkoutSet
    let repsOnly: Bool
    @FocusState private var focusedSetField: FocusedSetField?

    var body: some View {
        WorkoutSetView(focusedSetField: $focusedSetField, workoutSet: workoutSet, repsOnly: repsOnly)
    }
}
