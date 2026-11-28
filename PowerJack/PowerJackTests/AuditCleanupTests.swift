//
//  AuditCleanupTests.swift
//  PowerJackTests
//
//  Temporary files PowerJack leaves behind, and the watch's program copies on the iPhone's lists.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct AuditCleanupTests {
    @Test("Old temporary files of one kind go, and nothing else in the folder is touched")
    func removesOnlyMatchingTemporaryFiles() throws {
        let folder = URL.temporaryDirectory
        let tag = UUID().uuidString
        let names = ["pjtest-\(tag)-a.snapshot", "pjtest-\(tag)-b.snapshot", "pjtest-\(tag)-c.csv", "other-\(tag).snapshot"]
        for name in names {
            try Data("x".utf8).write(to: folder.appending(path: name))
        }
        defer { for name in names { try? FileManager.default.removeItem(at: folder.appending(path: name)) } }

        FileManager.default.removeTemporaryFiles(prefix: "pjtest-\(tag)", suffix: ".snapshot")

        let left = names.filter { FileManager.default.fileExists(atPath: folder.appending(path: $0).path(percentEncoded: false)) }
        #expect(left == ["pjtest-\(tag)-c.csv", "other-\(tag).snapshot"])
    }

    @Test("The iPhone's program lists leave out the watch's copies")
    func ownProgramsOnly() throws {
        let scenario = PowerJackSeed.weekOneProgress()
        let context = scenario.container.mainContext
        let all = try context.fetch(FetchDescriptor<Program>())
        let copy = try #require(all.first)
        copy.fromSnapshotValue = true
        try context.save()

        let own = try context.fetch(FetchDescriptor<Program>(predicate: Program.ownRows))

        #expect(own.count == all.count - 1)
        #expect(!own.contains { $0 === copy })
    }
}
