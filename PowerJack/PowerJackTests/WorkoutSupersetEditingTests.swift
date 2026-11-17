//
//  WorkoutSupersetEditingTests.swift
//  PowerJackTests
//
//  Supersets changed from the workout's ••• menu. The exercise the menu was opened from always leads
//  the superset it joins, an exercise taken out goes just before its superset, supersets are lettered
//  by position, and logged sets are never touched.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct WorkoutSupersetEditingTests {
    /// Held by the suite instance so models stay valid for the whole test.
    private let container = PowerJackSeed.makeInMemoryContainer()

    @Test("Each exercise on its own and each superset is one choice, leaving out the exercise's own")
    func choices() throws {
        let workout = try makeExampleWorkout()

        let choices = workout.supersetChoices(for: workout.workoutExercises[0])

        #expect(choices.map(names) == [
            ["Barbell Bench Press"],
            ["Dumbbell Chest Fly"],
            ["Bodyweight Pull Up", "Push Ups"],
            ["Dumbbell Curls", "Dumbbell Skull Crushers"],
        ])
    }

    @Test("Joining the next exercise moves nothing, and the supersets are lettered again by position")
    func joinNextExercise() throws {
        let workout = try makeExampleWorkout()
        let swing = workout.workoutExercises[0]

        workout.addToSuperset(swing, with: [workout.workoutExercises[1]])

        #expect(layout(of: workout) == [
            "Kettlebell Swing (A)",
            "Barbell Bench Press (A)",
            "Dumbbell Chest Fly",
            "Bodyweight Pull Up (B)",
            "Push Ups (B)",
            "Dumbbell Curls (C)",
            "Dumbbell Skull Crushers (C)",
        ])
    }

    @Test("Joining a later superset brings all of it up behind the exercise the menu was opened from")
    func joinLaterSuperset() throws {
        let workout = try makeExampleWorkout()
        let swing = workout.workoutExercises[0]
        let supersetB = workout.supersets[1]
        let supersetID = try #require(supersetB[0].supersetID)

        workout.addToSuperset(swing, with: supersetB)

        #expect(layout(of: workout) == [
            "Kettlebell Swing (A)",
            "Dumbbell Curls (A)",
            "Dumbbell Skull Crushers (A)",
            "Barbell Bench Press",
            "Dumbbell Chest Fly",
            "Bodyweight Pull Up (B)",
            "Push Ups (B)",
        ])
        // It's still the same superset, now with one more exercise.
        #expect(workout.superset(supersetID)?.count == 3)
        #expect(workout.workoutExercises.map(\.order) == Array(0..<7))
    }

    @Test("Joining an earlier exercise brings it down behind the exercise the menu was opened from")
    func joinEarlierExercise() throws {
        let workout = try makeExampleWorkout()
        let fly = workout.workoutExercises[2]

        workout.addToSuperset(fly, with: [workout.workoutExercises[0]])

        #expect(layout(of: workout).prefix(3) == [
            "Barbell Bench Press",
            "Dumbbell Chest Fly (A)",
            "Kettlebell Swing (A)",
        ])
    }

    @Test("An exercise taken out of its superset goes just before it")
    func removeGoesBefore() throws {
        let workout = try makeExampleWorkout()
        workout.addToSuperset(workout.workoutExercises[0], with: workout.supersets[1])
        let curls = workout.workoutExercises[1]

        workout.removeFromSuperset(curls)

        #expect(layout(of: workout).prefix(4) == [
            "Dumbbell Curls",
            "Kettlebell Swing (A)",
            "Dumbbell Skull Crushers (A)",
            "Barbell Bench Press",
        ])
    }

    @Test("Taking out the second last exercise ends the superset")
    func removeEndsPair() throws {
        let workout = try makeExampleWorkout()
        let pushUps = workout.workoutExercises[4]

        workout.removeFromSuperset(pushUps)

        #expect(layout(of: workout).suffix(4) == [
            "Push Ups",
            "Bodyweight Pull Up",
            "Dumbbell Curls (A)",
            "Dumbbell Skull Crushers (A)",
        ])
        #expect(workout.workoutExercises[3].supersetID == nil)
        #expect(workout.workoutExercises[4].supersetID == nil)
    }

    @Test("Removing a superset leaves its exercises on their own, in the same order")
    func removeWholeSuperset() throws {
        let workout = try makeExampleWorkout()
        let supersetID = try #require(workout.supersets[0][0].supersetID)

        workout.removeSuperset(supersetID)

        #expect(workout.superset(supersetID) == nil)
        #expect(layout(of: workout) == [
            "Kettlebell Swing",
            "Barbell Bench Press",
            "Dumbbell Chest Fly",
            "Bodyweight Pull Up",
            "Push Ups",
            "Dumbbell Curls (A)",
            "Dumbbell Skull Crushers (A)",
        ])
    }

    @Test("Reordering inside a superset leaves the rest of the workout where it was")
    func reorderInsideSuperset() throws {
        let workout = try makeExampleWorkout()
        workout.addToSuperset(workout.workoutExercises[0], with: workout.supersets[1])
        let supersetID = try #require(workout.workoutExercises[0].supersetID)

        // Kettlebell Swing to the end of its superset.
        workout.moveExercises(inSuperset: supersetID, from: IndexSet(integer: 0), to: 3)

        #expect(layout(of: workout) == [
            "Dumbbell Curls (A)",
            "Dumbbell Skull Crushers (A)",
            "Kettlebell Swing (A)",
            "Barbell Bench Press",
            "Dumbbell Chest Fly",
            "Bodyweight Pull Up (B)",
            "Push Ups (B)",
        ])
    }

    @Test("Mid-workout, logged sets stay as they were and the new superset goes round by round")
    func liveWorkoutKeepsLoggedSets() throws {
        let workout = try makeExampleWorkout()
        workout.startAndCascade()
        let swing = workout.workoutExercises[0]
        let bench = workout.workoutExercises[1]
        swing.completeSet(swing.workingSets[0])
        let logged = swing.workingSets[0]
        let before = (logged.status, logged.reps, logged.weightTenthsPounds)

        workout.addToSuperset(swing, with: [bench])

        #expect(swing.supersetPartners.first === bench)
        #expect(logged.status == .complete)
        #expect((logged.status, logged.reps, logged.weightTenthsPounds) == before)
        // Kettlebell Swing's first set is done, so it's the Bench Press's turn.
        #expect(workout.currentSet?.workoutSet === bench.workingSets[0])
    }

    @Test("A finished exercise isn't offered, and a finished workout can't change")
    func finishedIsLeftAlone() throws {
        let workout = try makeExampleWorkout()
        workout.startAndCascade()
        let bench = workout.workoutExercises[1]
        bench.skipRemainingSets()

        #expect(!workout.supersetChoices(for: workout.workoutExercises[0]).contains { $0.contains { $0 === bench } })

        workout.skipAndCascade()
        let before = layout(of: workout)
        workout.addToSuperset(workout.workoutExercises[0], with: [workout.workoutExercises[2]])
        workout.removeFromSuperset(workout.workoutExercises[3])
        #expect(!workout.canEditSupersets)
        #expect(layout(of: workout) == before)
    }

    // MARK: Helpers

    /// Kettlebell Swing, Bench Press, Chest Fly, a superset of Pull Up and Push Ups, then one of Curls and
    /// Skull Crushers. Each has two working sets of 10 and no warmups.
    private func makeExampleWorkout() throws -> Workout {
        let workout = Workout(order: 0)
        container.mainContext.insert(workout)
        let first = UUID()
        let second = UUID()
        let plan: [(name: String, superset: UUID?)] = [
            ("Kettlebell Swing", nil),
            ("Barbell Bench Press", nil),
            ("Dumbbell Chest Fly", nil),
            ("Bodyweight Pull Up", first),
            ("Push Ups", first),
            ("Dumbbell Curls", second),
            ("Dumbbell Skull Crushers", second),
        ]
        for entry in plan {
            let exercise = Exercise(
                exerciseName: entry.name,
                exerciseEquipment: .dumbbell,
                primaryMuscleFocus: .biceps,
                fatigueLevel: .moderate
            )
            let workoutExercise = try #require(workout.addWorkoutExercise(exercise: exercise))
            workoutExercise.setSuperset(entry.superset)
            for _ in 0..<2 {
                _ = workoutExercise.addSet(plannedReps: 10, plannedWeightTenthsPounds: 300)
            }
        }
        try container.mainContext.save()
        return workout
    }

    private func names(_ group: [WorkoutExercise]) -> [String] {
        group.compactMap { $0.exercise?.exerciseName }
    }

    /// Each exercise in order, with its superset's letter.
    private func layout(of workout: Workout) -> [String] {
        workout.workoutExercises.map { workoutExercise in
            let name = workoutExercise.exercise?.exerciseName ?? ""
            let group = workout.group(of: workoutExercise)
            guard group.count > 1 else { return name }
            return "\(name) (\(workout.supersetLetter(for: group)))"
        }
    }
}
