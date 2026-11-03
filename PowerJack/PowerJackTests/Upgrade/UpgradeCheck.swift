//
//  UpgradeCheck.swift
//  PowerJackTests
//
//  Checks that a store saved by an older version still holds everything the lifter did,
//  and that today's code can keep training on it.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

/// What a lifter's store holds. Old versions write it next to their store with
/// scripts/upgrade/UpgradeFixtureWriter.swift, which reads the same fields the same way.
struct UpgradeManifest: Codable {
    var programs: [String]
    var completedWorkouts: Int
    var completedSets: Int
    var loggedVolume: Int
    var feedback: Int
    var workoutLogs: Int
    var userExercises: [String]
    var templates: [String]

    init(context: ModelContext) throws {
        let sets = try context.fetch(FetchDescriptor<WorkoutSet>()).filter { $0.status == .complete }
        programs = try context.fetch(FetchDescriptor<Program>()).map(\.status.rawValue).sorted()
        completedWorkouts = try context.fetch(FetchDescriptor<Workout>()).filter { $0.status == .complete }.count
        completedSets = sets.count
        loggedVolume = sets.reduce(0) { $0 + ($1.reps ?? 0) * ($1.weightTenthsPounds ?? 0) }
        feedback = try context.fetchCount(FetchDescriptor<ExerciseFeedback>())
        workoutLogs = try context.fetchCount(FetchDescriptor<WorkoutLog>())
        userExercises = try context.fetch(FetchDescriptor<Exercise>()).filter(\.userCreated).map(\.exerciseName).sorted()
        templates = try context.fetch(FetchDescriptor<TemplateProgram>()).filter { $0.catalogID == nil }.map(\.templateName).sorted()
    }
}

@MainActor
enum UpgradeCheck {
    /// Compares the upgraded store with what `version` saved, then finishes the running workout.
    static func verify(_ container: ModelContainer, against saved: UpgradeManifest, from version: String) throws {
        let context = container.mainContext
        let upgraded = try UpgradeManifest(context: context)

        #expect(upgraded.programs == saved.programs, "Programs from \(version)")
        #expect(upgraded.completedWorkouts == saved.completedWorkouts, "Finished workouts from \(version)")
        #expect(upgraded.completedSets == saved.completedSets, "Logged sets from \(version)")
        #expect(upgraded.loggedVolume == saved.loggedVolume, "Logged weights and reps from \(version)")
        #expect(upgraded.feedback == saved.feedback, "Exercise feedback from \(version)")
        #expect(upgraded.workoutLogs == saved.workoutLogs, "Volume history from \(version)")
        #expect(upgraded.userExercises == saved.userExercises, "Own exercises from \(version)")
        #expect(upgraded.templates == saved.templates, "Own templates from \(version)")

        // The lifter picks up where they left off.
        let program = try #require(try context.fetch(FetchDescriptor<Program>()).active, "No running program from \(version)")
        let workout = try #require(program.nextWorkout, "No next workout from \(version)")
        if workout.status == .planned {
            workout.startAndCascade()
        }
        for exercise in workout.workoutExercises where exercise.status != .complete {
            for set in exercise.workoutSets where set.status != .complete {
                set.reps = 10
                set.weightTenthsPounds = 1050
                set.complete()
            }
            exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
            exercise.completeAndCascade()
        }
        _ = program.finishWorkout(workout)
        try context.save()

        let trained = try UpgradeManifest(context: context)
        #expect(trained.completedWorkouts == upgraded.completedWorkouts + 1, "Finishing a workout after upgrading from \(version)")
        #expect(program.nextWorkout != nil, "The program from \(version) moves on to its next workout")
    }
}
