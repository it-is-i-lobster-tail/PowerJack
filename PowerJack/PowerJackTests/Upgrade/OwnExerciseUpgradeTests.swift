//
//  OwnExerciseUpgradeTests.swift
//  PowerJackTests
//
//  A lifter on an older version who made their own "Weighted Dips" gets the built-in one on
//  upgrading, with every template, program and logged set that used theirs.
//

import Foundation
import SQLite3
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct OwnExerciseUpgradeTests {
    @Test("An own Weighted Dips saved by an older version becomes the built-in one and keeps its history", arguments: UpgradeFixture.bundled)
    func ownCopyBecomesBuiltIn(from fixture: UpgradeFixture) throws {
        // The fixture's own exercise, renamed the way the lifter might have typed it.
        let url = try copyStore(of: fixture)
        try execute("UPDATE ZEXERCISE SET ZEXERCISENAME = 'weighted dips' WHERE ZUSERCREATEDVALUE = 1", on: url)

        let configuration = ModelConfiguration(schema: PowerJackSchema.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PowerJackSchema.schema, configurations: [configuration])
        Self.open.append(container)
        let context = container.mainContext
        try ExerciseCatalog.seed(in: context)
        try TemplateCatalog.seed(in: context)

        let dips = try context.fetch(FetchDescriptor<Exercise>()).filter { $0.catalogID == "weighted-dip" }
        #expect(dips.count == 1, "\(fixture.version)")
        let dip = try #require(dips.first)
        #expect(dip.exerciseName == "Weighted Dips" && !dip.userCreated && dip.equipment == .loadableBodyweight, "\(fixture.version)")
        #expect(dip.templateExercisesValue?.count == 3, "\(fixture.version)")
        #expect(dip.workoutExercisesValue?.count == 6, "\(fixture.version)")

        // Everything else the lifter saved is still there, and nothing of theirs is left behind.
        var saved = try JSONDecoder().decode(UpgradeManifest.self, from: Data(contentsOf: fixture.manifest))
        saved.userExercises = []
        #expect(try UpgradeManifest(context: context) == saved, "\(fixture.version)")
    }

    /// Upgraded stores stay open for the whole run, like `HostedView.makeStore()`.
    private static var open: [ModelContainer] = []

    private func copyStore(of fixture: UpgradeFixture) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "OwnExerciseUpgradeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture.store, to: url)
        return url
    }

    private func execute(_ sql: String, on url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            throw SQLiteError(message: "Could not open \(url.lastPathComponent)")
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK, sqlite3_changes(database) == 1 else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(database)))
        }
    }

    private struct SQLiteError: Error {
        let message: String
    }
}
