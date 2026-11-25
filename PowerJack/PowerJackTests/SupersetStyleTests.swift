//
//  SupersetStyleTests.swift
//  PowerJackTests
//
//  Supersets are colored by letter, VoiceOver names every partner, and a workout can start at most five.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
struct SupersetStyleTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("VoiceOver hears every partner's name")
    func fullLabel() {
        let long = ["Cable Overhead Extension", "Dumbbell Lateral Raise"]
        #expect(SupersetStyle.fullLabel(partners: long) == "Superset with Cable Overhead Extension and Dumbbell Lateral Raise")
    }

    @Test("A to E each get their own color, and older days past E cycle back through them")
    func colors() {
        #expect(SupersetStyle.colors == [.blue, .purple, .teal, .orange, .pink])
        #expect(Set(SupersetStyle.colors.map(\.description)).count == SupersetStyle.maxPerWorkout)
        #expect(SupersetStyle.color(at: 0) == .blue)
        #expect(SupersetStyle.color(at: 4) == .pink)
        #expect(SupersetStyle.color(at: 5) == .blue)
        #expect(SupersetStyle.color(at: 7) == .teal)
    }

    @Test("Each exercise knows its superset's place and color, and one on its own has none")
    func workoutExerciseColor() throws {
        let workout = try makeWorkout(supersets: 2, loneExercises: 1)
        let exercises = workout.workoutExercises

        #expect(exercises.map(\.supersetIndex) == [0, 0, 1, 1, nil])
        #expect(exercises.map(\.supersetColor) == [.blue, .blue, .purple, .purple, nil])
    }

    @Test("At five supersets, only those can be joined, and a new one can't start")
    func workoutCap() throws {
        let workout = try makeWorkout(supersets: 5, loneExercises: 2)
        let lone = workout.workoutExercises[10]
        #expect(!workout.canStartSuperset)

        let choices = workout.supersetChoices(for: lone)
        #expect(choices.count == 5)
        #expect(choices.allSatisfy { $0.count > 1 })

        // Pairing with the other lone exercise is refused; joining A still works.
        workout.addToSuperset(lone, with: [workout.workoutExercises[11]])
        #expect(workout.supersets.count == 5)
        workout.addToSuperset(lone, with: workout.supersets[0])
        #expect(workout.supersets.count == 5)
        #expect(workout.group(of: lone).count == 3)
    }

    @Test("Below five, an exercise on its own can still start one")
    func workoutBelowCap() throws {
        let workout = try makeWorkout(supersets: 4, loneExercises: 2)
        #expect(workout.canStartSuperset)
        #expect(workout.supersetChoices(for: workout.workoutExercises[8]).contains { $0.count == 1 })
    }

    @Test("A day saved with more than five keeps working: letters go on past E and colors cycle")
    func olderDayPastFive() throws {
        let workout = try makeWorkout(supersets: 7, loneExercises: 0)

        #expect(workout.supersets.map { workout.supersetLetter(for: $0) } == ["A", "B", "C", "D", "E", "F", "G"])
        #expect(workout.supersets.map { $0[0].supersetColor } == [.blue, .purple, .teal, .orange, .pink, .blue, .purple])
        #expect(!workout.canStartSuperset)
    }

    // MARK: Helpers

    /// `supersets` pairs of exercises, each pair its own superset, then `loneExercises` on their own.
    private func makeWorkout(supersets: Int, loneExercises: Int) throws -> Workout {
        let workout = Workout(order: 0)
        container.mainContext.insert(workout)
        let plan: [UUID?] = (0..<supersets).flatMap { _ in
            let id = UUID()
            return [id, id]
        } + Array(repeating: nil, count: loneExercises)
        for (index, supersetID) in plan.enumerated() {
            let exercise = Exercise(
                exerciseName: "Exercise \(index)",
                exerciseEquipment: .dumbbell,
                primaryMuscleFocus: .biceps,
                fatigueLevel: .moderate
            )
            let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
            workoutExercise.setSuperset(supersetID)
            _ = workoutExercise.addSet(plannedReps: 10, plannedWeightTenthsPounds: 300)
        }
        try container.mainContext.save()
        return workout
    }
}
