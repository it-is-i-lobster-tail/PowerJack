//
//  UpgradeFixtureWriter.swift
//  PowerJackTests (old versions only)
//
//  scripts/upgrade/upgrade-test.sh copies this into an old version's PowerJackTests folder
//  and runs it inside that version's installed app. It trains like a lifter would, saves
//  into the app's real store, and writes upgrade-manifest.json next to it, so the current
//  version can check that every bit of it survives the upgrade.
//
//  It must compile against every released version, so it only uses APIs that 1.0 already
//  had. Keep it that way: never call anything newer here.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct UpgradeFixtureWriter {
    @Test func writeLifterData() throws {
        // The same store the app opened when it launched, with iCloud Backup on like the app.
        let container = try PowerJackSchema.makeModelContainer(syncsWithICloud: true)
        let context = container.mainContext

        let catalog = try context.fetch(FetchDescriptor<Exercise>())
            .filter { !$0.userCreated && $0.exerciseEquipment == .barbell }
            .sorted { $0.exerciseName < $1.exerciseName }
        try #require(catalog.count >= 3, "The app's launch should have seeded the built-in exercises")

        let curl = Exercise(
            exerciseName: "Upgrade Curl",
            exerciseEquipment: .dumbbell,
            primaryMuscleFocus: .biceps,
            userCreated: true,
            minReps: 8,
            maxReps: 12
        )
        context.insert(curl)

        // A finished one-week program from a built-in template.
        let builtIn = try #require(
            try context.fetch(FetchDescriptor<TemplateProgram>())
                .filter { $0.catalogID != nil }
                .sorted { $0.templateName < $1.templateName }
                .first
        )
        let finished = Program(programLengthWeeks: 1, templateProgram: builtIn)
        try context.insertAndSave(finished)
        finished.start()
        for _ in 0..<builtIn.workoutsPerWeek {
            let workout = try #require(finished.nextWorkout)
            workout.startAndCascade()
            log(workout, reps: 8, weightTenthsPounds: 1350)
            _ = finished.finishWorkout(workout)
        }

        // A running program on the lifter's own template: week 1 done, week 2 mid-workout.
        let template = TemplateProgram(templateName: "Upgrade Template", workoutsPerWeek: 3, templateMuscleFocus: [.chest, .back])
        template.templateWorkoutsValue = (0..<3).map { order in
            let workout = TemplateWorkout(order: order)
            workout.templateExercisesValue = [
                TemplateExercise(exercise: catalog[order % catalog.count], order: 0),
                TemplateExercise(exercise: curl, order: 1),
            ]
            return workout
        }
        context.insert(template)

        let running = Program(programLengthWeeks: 4, templateProgram: template)
        try context.insertAndSave(running)
        running.start()
        for _ in 0..<3 {
            let workout = try #require(running.nextWorkout)
            workout.startAndCascade()
            log(workout, reps: 10, weightTenthsPounds: 1000)
            _ = running.finishWorkout(workout)
        }
        let inProgress = try #require(running.nextWorkout)
        inProgress.startAndCascade()
        if let first = inProgress.workoutExercises.first {
            for set in first.workoutSets {
                set.reps = 9
                set.weightTenthsPounds = 1050
                set.complete()
            }
        }
        try context.save()

        let manifest = try Manifest(context: context)
        let url = URL.applicationSupportDirectory.appending(path: "upgrade-manifest.json")
        try JSONEncoder().encode(manifest).write(to: url)
        print("Upgrade fixture: \(manifest)")
    }

    private func log(_ workout: Workout, reps: Int, weightTenthsPounds: Int) {
        for exercise in workout.workoutExercises {
            for set in exercise.workoutSets {
                set.reps = reps
                set.weightTenthsPounds = weightTenthsPounds
                set.complete()
            }
            exercise.addFeedback(feedback: ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none))
            exercise.completeAndCascade()
        }
    }

    /// Matches `UpgradeManifest` in the current PowerJackTests.
    private struct Manifest: Codable {
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
}
