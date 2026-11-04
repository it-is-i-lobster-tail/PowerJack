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

/// A store an older version saved, and what it held.
struct UpgradeFixture: CustomTestStringConvertible, Sendable {
    let version: String
    let store: URL
    let manifest: URL

    var testDescription: String { version }

    /// upgrade-<version>.store and .json, shipped in UpgradeFixtures.
    nonisolated static let bundled: [UpgradeFixture] = {
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
            .sorted(by: oldestFirst)
    }()

    /// <version>/default.store and upgrade-manifest.json, which the Upgrade tests workflow copies
    /// off the simulator after installing this version over each older one and opening it.
    nonisolated static let installed: [UpgradeFixture] = {
        guard let path = ProcessInfo.processInfo.environment["POWERJACK_UPGRADED_STORES"] else { return [] }
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: URL(filePath: path, directoryHint: .isDirectory),
            includingPropertiesForKeys: nil
        )) ?? []
        return folders
            .map { folder in
                UpgradeFixture(
                    version: folder.lastPathComponent,
                    store: folder.appending(path: "default.store"),
                    manifest: folder.appending(path: "upgrade-manifest.json")
                )
            }
            .sorted(by: oldestFirst)
    }()

    private nonisolated static func oldestFirst(_ a: UpgradeFixture, _ b: UpgradeFixture) -> Bool {
        a.version.compare(b.version, options: .numeric) == .orderedAscending
    }

    private final class BundleToken {}
}

@MainActor
enum UpgradeStore {
    /// Upgraded stores stay open for the whole run, like `HostedView.makeStore()`.
    private static var open: [ModelContainer] = []

    /// Opens a copy, so the fixture never changes, seeds it like the app's launch, and checks it.
    static func openAndVerify(_ fixture: UpgradeFixture) throws -> ModelContainer {
        let folder = URL.temporaryDirectory.appending(path: "UpgradeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture.store, to: url)

        let configuration = ModelConfiguration(schema: PowerJackSchema.schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: PowerJackSchema.schema, configurations: [configuration])
        open.append(container)
        try ExerciseCatalog.seed(in: container.mainContext)
        try TemplateCatalog.seed(in: container.mainContext)

        let saved = try JSONDecoder().decode(UpgradeManifest.self, from: Data(contentsOf: fixture.manifest))
        try UpgradeCheck.verify(container, against: saved, from: fixture.version)
        return container
    }
}

@MainActor
struct UpgradeTests {
    @Test("Stores saved by older versions ship with the tests")
    func fixturesShip() {
        #expect(UpgradeFixture.bundled.count >= 2, "\(UpgradeFixture.bundled.map(\.version))")
    }

    @Test("A store saved by an older version opens, keeps the lifter's data and keeps training", arguments: UpgradeFixture.bundled)
    func upgrade(from fixture: UpgradeFixture) async throws {
        let container = try UpgradeStore.openAndVerify(fixture)

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
}

/// Runs only in the Upgrade tests workflow, on the stores this version upgraded on the simulator.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["POWERJACK_UPGRADED_STORES"] != nil))
struct InstalledUpgradeTests {
    @Test("An installed upgrade keeps the old version's data and keeps training", arguments: UpgradeFixture.installed)
    func installedUpgrade(from fixture: UpgradeFixture) throws {
        _ = try UpgradeStore.openAndVerify(fixture)
        // Tells the script this version's check passed. Any failed expectation fails the run too.
        let folder = fixture.store.deletingLastPathComponent()
        try Data().write(to: folder.appending(path: "verified"))
    }
}
