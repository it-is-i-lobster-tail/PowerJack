//
//  SyncPacingTests.swift
//  PowerJackTests
//
//  Work that runs on every sync or settings change is paced: one tidy-up for a burst of iCloud
//  imports or watch messages, and settings followers only hear about real settings changes.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct SyncPacingTests {
    @Test("A burst of changes tidies up once, after a moment, not on every change")
    func tidyUpRunsOncePerBurst() async throws {
        let store = PowerJackStore(inMemory: true)
        let context = store.container!.mainContext
        let entry = try #require(ExerciseCatalog.entries.first)
        // Another device's seeded copy of a built-in exercise, newer so the dedupe removes it.
        let copy = entry.makeExercise()
        copy.createdAtValue = .now.addingTimeInterval(60)
        context.insert(copy)
        try context.save()
        func copies() throws -> Int {
            try context.fetch(FetchDescriptor<Exercise>()).count { $0.catalogID == entry.id }
        }
        #expect(try copies() == 2)

        for _ in 0..<5 { store.scheduleTidyUp(after: "iCloud import") }
        #expect(try copies() == 2)

        try await Task.sleep(for: PowerJackStore.tidyUpInterval + .milliseconds(500))
        #expect(try copies() == 1)
    }

    @Test("Settings followers hear about a setting changing, not about other UserDefaults writes")
    func settingsChangesOnly() async throws {
        let suite = "SyncPacingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsSync.startWatching(defaults)
        var heard = 0
        let observer = NotificationCenter.default.addObserver(forName: SettingsSync.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { heard += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        defaults.set(3, forKey: "sync.appliedWatchChanges")
        try await Task.sleep(for: .milliseconds(200))
        #expect(heard == 0)

        defaults.set(WeightUnit.kilograms.rawValue, forKey: AppSettings.Key.weightUnit)
        try await Task.sleep(for: .milliseconds(200))
        #expect(heard == 1)

        // The same value again isn't a change.
        defaults.set(WeightUnit.kilograms.rawValue, forKey: AppSettings.Key.weightUnit)
        try await Task.sleep(for: .milliseconds(200))
        #expect(heard == 1)
    }
}
