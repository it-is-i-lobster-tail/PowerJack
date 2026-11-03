//
//  UpgradeCheck.swift
//  PowerJackTests
//
//  Checks that a store saved by an older version still holds everything the lifter did,
//  and that today's code can keep training on it.
//

import Foundation
import SwiftData
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

struct UpgradeProblems: Error, CustomStringConvertible {
    let version: String
    let problems: [String]
    var description: String { "Upgrade from \(version): " + problems.joined(separator: "; ") }
}

@MainActor
enum UpgradeCheck {
    /// Compares the upgraded store with what `version` saved, then finishes the running workout.
    /// Throws every difference at once, so a failed upgrade shows all of what it lost.
    static func verify(_ container: ModelContainer, against saved: UpgradeManifest, from version: String) throws {
        let context = container.mainContext
        let upgraded = try UpgradeManifest(context: context)
        var problems: [String] = []
        func check<Value: Equatable>(_ name: String, _ before: Value, _ after: Value) {
            if before != after { problems.append("\(name): \(before) before, \(after) after") }
        }

        check("Programs", saved.programs, upgraded.programs)
        check("Finished workouts", saved.completedWorkouts, upgraded.completedWorkouts)
        check("Logged sets", saved.completedSets, upgraded.completedSets)
        check("Logged weight x reps", saved.loggedVolume, upgraded.loggedVolume)
        check("Exercise feedback", saved.feedback, upgraded.feedback)
        check("Volume history", saved.workoutLogs, upgraded.workoutLogs)
        check("Own exercises", saved.userExercises, upgraded.userExercises)
        check("Own templates", saved.templates, upgraded.templates)

        // The lifter picks up where they left off.
        if let program = try context.fetch(FetchDescriptor<Program>()).active, let workout = program.nextWorkout {
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
            check("Finished workouts after one more", upgraded.completedWorkouts + 1, trained.completedWorkouts)
            if program.nextWorkout == nil { problems.append("The program doesn't move on to its next workout") }
        } else {
            problems.append("No running program with a next workout")
        }

        guard problems.isEmpty else {
            throw UpgradeProblems(version: version, problems: problems)
        }
    }
}
