//
//  UpgradeTests.swift
//  PowerJackTests
//
//  Opens stores saved by older versions with today's model, the way the app does after an
//  App Store or TestFlight update. Each fixture in UpgradeFixtures is a copy of the store an
//  old version saved, made by the Upgrade tests workflow (see scripts/upgrade/README.md).
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

struct UpgradeFixture: CustomTestStringConvertible, Sendable {
    let version: String
    let store: URL
    let manifest: URL

    var testDescription: String { version }

    static let all: [UpgradeFixture] = {
        let bundle = Bundle(for: BundleToken.self)
        let stores = (bundle.urls(forResourcesWithExtension: "store", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "store", subdirectory: "UpgradeFixtures") ?? [])
        return stores
            .filter { $0.lastPathComponent.hasPrefix("upgrade-") }
            .map { store in
                UpgradeFixture(
                    version: String(store.deletingPathExtension().lastPathComponent.dropFirst("upgrade-".count)),
                    store: store,
                    manifest: store.deletingPathExtension().appendingPathExtension("json")
                )
            }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
    }()

    private final class BundleToken {}
}

@MainActor
struct UpgradeTests {
    /// Upgraded stores stay open for the whole run, like `HostedView.makeStore()`.
    private static var openStores: [ModelContainer] = []

    @Test("Stores saved by older versions ship with the tests")
    func fixturesShip() {
        #expect(UpgradeFixture.all.count >= 2, "\(UpgradeFixture.all.map(\.version))")
    }

    @Test("A store saved by an older version opens, keeps the lifter's data and keeps training", arguments: UpgradeFixture.all)
    func upgrade(from fixture: UpgradeFixture) async throws {
        let container = try open(fixture)
        let saved = try JSONDecoder().decode(UpgradeManifest.self, from: Data(contentsOf: fixture.manifest))
        try UpgradeCheck.verify(container, against: saved, from: fixture.version)

        // The first screen shows the upgraded program, or reopens it where the lifter left off.
        let screen = try await HostedView(
            PowerJackRootView()
                .modelContainer(container)
                .environment(PowerJackStore(inMemory: true))
        )
        defer { screen.close() }
        let shown = await screen.waitUntil { screen.labels.contains { $0.contains("Upgrade Template") } }
        #expect(shown, "\(fixture.version): \(screen.labels)")
    }

    /// Opens a copy, so the shipped fixture never changes, then seeds like the app's launch.
    private func open(_ fixture: UpgradeFixture) throws -> ModelContainer {
        let folder = URL.temporaryDirectory.appending(path: "UpgradeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture.store, to: url)

        let configuration = ModelConfiguration(schema: PowerJackSchema.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PowerJackSchema.schema, configurations: [configuration])
        Self.openStores.append(container)
        try ExerciseCatalog.seed(in: container.mainContext)
        try TemplateCatalog.seed(in: container.mainContext)
        return container
    }
}

/// Runs only in the Upgrade tests workflow, after an old version saved its data on the
/// simulator and this version was installed over it and launched.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["POWERJACK_UPGRADE_FROM"] != nil))
struct InstalledUpgradeTests {
    @Test("The installed upgrade keeps the old version's data and keeps training")
    func installedUpgrade() throws {
        let version = ProcessInfo.processInfo.environment["POWERJACK_UPGRADE_FROM"] ?? "?"
        let folder = URL.applicationSupportDirectory
        let saved = try JSONDecoder().decode(
            UpgradeManifest.self,
            from: Data(contentsOf: folder.appending(path: "upgrade-manifest.json"))
        )
        // The app's real store, opened exactly as the app opens it.
        let store = PowerJackStore(inMemory: false)
        try UpgradeCheck.verify(store.container, against: saved, from: version)
        // Tells the script this check really ran.
        try Data(version.utf8).write(to: folder.appending(path: "upgrade-verified"))
    }
}
