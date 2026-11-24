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

    @Test("Movement upgrade preserves a renamed bench and a custom exercise with its original catalog name")
    func renamedBuiltInAndSameNameCustom() throws {
        let fixture = try #require(UpgradeFixture.bundled.first { $0.version == "1.0.51" })
        let url = try copyStore(of: fixture)
        try execute("UPDATE ZEXERCISE SET ZEXERCISENAME = 'Meet Bench', ZCUSTOMRESTTIMEVALUE = 137 WHERE ZCATALOGID = 'barbell-bench-press'", on: url)
        try execute("UPDATE ZEXERCISE SET ZEXERCISENAME = 'Barbell Bench Press' WHERE ZUSERCREATEDVALUE = 1", on: url)
        let config = ModelConfiguration(schema: PowerJackSchema.schema, url: url, cloudKitDatabase: .none)
        let linkedRows: Set<UUID>
        let customRows: Set<UUID>
        do {
            let container = try ModelContainer(for: PowerJackSchema.schema, configurations: [config])
            let rows = try container.mainContext.fetch(FetchDescriptor<Exercise>())
            let bench = try #require(rows.first { $0.catalogID == "barbell-bench-press" })
            let custom = try #require(rows.first { $0.userCreated })
            let benchID = bench.persistentModelID
            let customID = custom.persistentModelID
            linkedRows = Set((bench.workoutExercisesValue ?? []).compactMap(\.syncIDValue))
            customRows = Set((custom.workoutExercisesValue ?? []).compactMap(\.syncIDValue))
            #expect(!linkedRows.isEmpty && !customRows.isEmpty)
            try ExerciseCatalog.seed(in: container.mainContext)
            let seeded = try container.mainContext.fetch(FetchDescriptor<Exercise>())
            #expect(seeded.first { $0.catalogID == "barbell-bench-press" }?.persistentModelID == benchID)
            #expect(seeded.first { $0.userCreated }?.persistentModelID == customID)
        }
        let reopened = try ModelContainer(for: PowerJackSchema.schema, configurations: [config])
        let rows = try reopened.mainContext.fetch(FetchDescriptor<Exercise>())
        let bench = try #require(rows.first { $0.catalogID == "barbell-bench-press" })
        let custom = try #require(rows.first { $0.userCreated })
        #expect(bench.exerciseName == "Meet Bench" && bench.customRestTimeValue == 137)
        #expect(bench.movementPattern == .horizontalPress && bench.jointActions?.count == 2)
        #expect(Set((bench.workoutExercisesValue ?? []).compactMap(\.syncIDValue)) == linkedRows)
        #expect(custom.exerciseName == "Barbell Bench Press" && custom.catalogID == nil)
        #expect(custom.movementPattern == nil && custom.executionStyle == nil && (custom.jointActions ?? []).isEmpty)
        #expect(Set((custom.workoutExercisesValue ?? []).compactMap(\.syncIDValue)) == customRows)
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
