//
//  SetInputLimitTests.swift
//  PowerJackTests
//
//  A set's weight box takes 0 to 1000 lb and its reps box 0 to 50. Larger entries never get typed.
//

import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
@Suite(.serialized)
struct SetInputLimitTests {
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("Reps input takes whole numbers from 0 to 50")
    func repsInput() {
        #expect(WorkoutSetView.repsInput("", previous: "8") == "")
        #expect(WorkoutSetView.repsInput("0", previous: "") == "0")
        #expect(WorkoutSetView.repsInput("50", previous: "5") == "50")
        #expect(WorkoutSetView.repsInput("12a", previous: "1") == "12")

        #expect(WorkoutSetView.repsInput("51", previous: "5") == "5")
        #expect(WorkoutSetView.repsInput("500", previous: "50") == "50")
        #expect(WorkoutSetView.repsInput("005", previous: "00") == "00")
    }

    @Test("Weight input takes 0 to 1000 to a tenth of a pound")
    func weightInput() {
        #expect(WorkoutSetView.weightInput("", previous: "5") == "")
        #expect(WorkoutSetView.weightInput("0", previous: "") == "0")
        #expect(WorkoutSetView.weightInput("1000", previous: "100") == "1000")
        #expect(WorkoutSetView.weightInput("999.5", previous: "999.") == "999.5")
        #expect(WorkoutSetView.weightInput("22,5", previous: "22,") == "22,5")
        #expect(WorkoutSetView.weightInput("135.", previous: "135") == "135.")

        #expect(WorkoutSetView.weightInput("1001", previous: "100") == "100")
        #expect(WorkoutSetView.weightInput("1000.5", previous: "1000.") == "1000.")
        #expect(WorkoutSetView.weightInput("10000", previous: "1000") == "1000")
        #expect(WorkoutSetView.weightInput("22.55", previous: "22.5") == "22.5")
        #expect(WorkoutSetView.weightInput("2.2.5", previous: "2.2") == "2.2")
        #expect(WorkoutSetView.weightInput("-5", previous: "") == "")
    }

    @Test("A set never stores weight above 1000 lb or reps above 50")
    func modelCaps() {
        let set = WorkoutSet(order: 0, plannedReps: nil, plannedWeightTenthsPounds: nil)
        set.start()

        set.weightInPounds = 1000
        #expect(set.weightTenthsPounds == 10_000)
        set.weightInPounds = 1000.1
        #expect(set.weightTenthsPounds == nil)

        set.reps = 50
        #expect(set.reps == 50)
        set.reps = 51
        #expect(set.reps == nil)
    }

    @Test("Typing past the limits into a set row keeps the last allowed value")
    func setRowRefusesLargeEntries() async throws {
        let workoutSet = try makeActiveSet()
        let screen = try await HostedView(SetHost(workoutSet: workoutSet).modelContainer(container))
        defer { screen.close() }

        #expect(await screen.type("1000", into: "Set 1 weight"))
        #expect(workoutSet.weightTenthsPounds == 10_000)
        #expect(await screen.type("1001", into: "Set 1 weight"))
        #expect(workoutSet.weightTenthsPounds == 10_000)

        #expect(await screen.type("50", into: "Set 1 reps"))
        #expect(workoutSet.reps == 50)
        #expect(await screen.type("51", into: "Set 1 reps"))
        #expect(workoutSet.reps == 50)
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

private struct SetHost: View {
    let workoutSet: WorkoutSet
    @FocusState private var focusedSetField: FocusedSetField?

    var body: some View {
        WorkoutSetView(focusedSetField: $focusedSetField, workoutSet: workoutSet)
    }
}
