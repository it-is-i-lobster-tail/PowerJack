//
//  SetFieldFocusTests.swift
//  PowerJackTests
//
//  Tapping a set's weight or reps box that already holds a number selects it,
//  so typing replaces the number instead of adding digits in front of it.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct SetFieldFocusTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    init() {
        // These read weights in pounds, whatever unit the simulator was last left in.
        UserDefaults.standard.set(WeightUnit.pounds.rawValue, forKey: AppSettings.Key.weightUnit)
    }

    @Test("Typing into a filled weight box replaces the weight")
    func weightIsReplaced() async throws {
        let workoutSet = try makeActiveSet()
        workoutSet.weightTenthsPounds = 1350
        let screen = try await HostedView(FocusHost(workoutSet: workoutSet).modelContainer(container))
        defer { screen.close() }

        #expect(await screen.focusAndType("140", into: "Set 1 weight"))
        #expect(workoutSet.weightTenthsPounds == 1400)
    }

    @Test("Typing into a filled reps box replaces the reps")
    func repsAreReplaced() async throws {
        let workoutSet = try makeActiveSet()
        workoutSet.reps = 9
        let screen = try await HostedView(FocusHost(workoutSet: workoutSet).modelContainer(container))
        defer { screen.close() }

        #expect(await screen.focusAndType("7", into: "Set 1 reps"))
        #expect(workoutSet.reps == 7)
    }

    private func makeActiveSet() throws -> WorkoutSet {
        let workout = Workout(order: 0)
        let exercise = Exercise(exerciseName: "Test", exerciseEquipment: .barbell, primaryMuscleFocus: .chest)
        let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
        let workoutSet = try #require(workoutExercise.addSet(plannedReps: 10, plannedWeightTenthsPounds: nil))
        container.mainContext.insert(workout)
        workout.startAndCascade()
        return workoutSet
    }
}

private struct FocusHost: View {
    let workoutSet: WorkoutSet
    @FocusState private var focusedSetField: FocusedSetField?

    var body: some View {
        WorkoutSetView(focusedSetField: $focusedSetField, workoutSet: workoutSet)
    }
}
