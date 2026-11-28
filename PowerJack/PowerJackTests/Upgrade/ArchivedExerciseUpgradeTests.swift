//
//  ArchivedExerciseUpgradeTests.swift
//  PowerJackTests
//
//  Stores saved before exercises could be archived load with nothing archived, and the lifter's own
//  exercise from each one can then be archived, reopened and merged without losing a row.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct ArchivedExerciseUpgradeTests {
    @Test("Old stores load with nothing archived, then archive and merge their own exercise", arguments: UpgradeFixture.bundled)
    func oldStoreArchivesAndMerges(from fixture: UpgradeFixture) throws {
        let url = try copyStore(of: fixture)

        let firstRows: Int
        do {
            let container = try open(url, keep: false)
            let context = container.mainContext
            try ExerciseCatalog.seed(in: context)
            try TemplateCatalog.seed(in: context)
            let exercises = try context.fetch(FetchDescriptor<Exercise>())
            #expect(!exercises.isEmpty && exercises.allSatisfy { $0.archivedAtValue == nil }, "\(fixture.version)")
            let own = try #require(exercises.first { $0.userCreated }, "\(fixture.version)")
            firstRows = (own.workoutExercisesValue ?? []).count + (own.templateExercisesValue ?? []).count
            #expect(firstRows > 0, "\(fixture.version)")
            #expect(try ExerciseRemoval.usage(of: own, in: context).isUsed, "\(fixture.version)")
            try ExerciseRemoval.archive(own, in: context)
        }

        do {
            let container = try open(url, keep: false)
            let context = container.mainContext
            let own = try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.userCreatedValue })).first)
            #expect(own.isArchived, "\(fixture.version)")
            #expect((own.workoutExercisesValue ?? []).count + (own.templateExercisesValue ?? []).count == firstRows, "\(fixture.version)")
            let row = try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == "barbell-row" })).first)
            try ExerciseRemoval.merge(own, into: row, in: context, defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        }

        let context = try open(url).mainContext
        #expect(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.userCreatedValue })).isEmpty, "\(fixture.version)")
        let row = try #require(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == "barbell-row" })).first)
        #expect((row.workoutExercisesValue ?? []).count + (row.templateExercisesValue ?? []).count >= firstRows, "\(fixture.version)")
        #expect(try context.fetch(FetchDescriptor<WorkoutExercise>()).allSatisfy { $0.exercise != nil }, "\(fixture.version)")
        #expect(try context.fetch(FetchDescriptor<TemplateExercise>()).allSatisfy { $0.exercise != nil }, "\(fixture.version)")
    }

    /// Stores stay open for the whole run, like `PowerJackSeed.makeInMemoryContainer()`.
    private static var kept: [ModelContainer] = []

    /// Only the last one is kept: an earlier one left open would see the next one's deletes.
    private func open(_ url: URL, keep: Bool = true) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: PowerJackSchema.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PowerJackSchema.schema, configurations: [configuration])
        if keep { Self.kept.append(container) }
        return container
    }

    private func copyStore(of fixture: UpgradeFixture) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "ArchivedExerciseUpgradeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture.store, to: url)
        return url
    }
}
