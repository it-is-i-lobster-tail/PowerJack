//
//  StoreRecoveryTests.swift
//  PowerJackTests
//
//  A store that won't open no longer stops the app: it shows a recovery screen and opens on a retry.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import PowerJack

@MainActor
struct StoreRecoveryTests {
    /// Fails until `opens` is set, like a store before the first unlock after a restart.
    private final class FlakyOpener {
        var opens = false
        var attempts = 0

        func open(inMemory: Bool, syncsWithICloud: Bool) throws -> ModelContainer {
            attempts += 1
            guard opens else { throw CocoaError(.fileReadNoPermission) }
            return try PowerJackStore.openContainer(inMemory: inMemory, syncsWithICloud: syncsWithICloud)
        }
    }

    @Test("A store that won't open leaves the app running with no container, and a retry opens it")
    func opensOnRetry() throws {
        let opener = FlakyOpener()
        let store = PowerJackStore(inMemory: true, opener: opener.open)

        #expect(store.container == nil)
        #expect(store.openError != nil)
        #expect(store.openFailureSummary?.contains("NSCocoaErrorDomain 257") == true)
        // Work that runs outside the screens skips quietly.
        store.tidyUpAfterSync(trigger: "test")
        store.scheduleTidyUp(after: "test")

        store.retryOpening()
        #expect(store.container == nil)
        #expect(opener.attempts == 2)

        opener.opens = true
        store.retryOpening()
        let container = try #require(store.container)
        #expect(store.openError == nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Exercise>()) > 0)

        // Once open, it isn't opened again.
        store.retryOpening()
        #expect(opener.attempts == 3)
        #expect(store.container === container)
    }

    @Test("The app shows the recovery screen, and Try Again brings back the app")
    func recoveryScreen() async throws {
        let opener = FlakyOpener()
        let store = PowerJackStore(inMemory: true, opener: opener.open)
        let screen = try await HostedView(PowerJackAppContent().environment(store))
        defer { screen.close() }

        #expect(screen.contains("PowerJack couldn't open your training data"), "\(screen.labels)")
        #expect(screen.contains("Share Diagnostics"), "\(screen.labels)")

        opener.opens = true
        #expect(await screen.tap("Try Again", settleFor: .milliseconds(800)), "\(screen.labels)")
        #expect(store.container != nil)
        #expect(!screen.contains("PowerJack couldn't open your training data"), "\(screen.labels)")
        #expect(screen.contains("Programs"), "\(screen.labels)")
    }
}
