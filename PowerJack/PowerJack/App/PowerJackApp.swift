// xcode: set sdk=iOS

//
//  PowerJackApp.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData

@main
struct PowerJackApp: App {
    /// Static so the Live Activity's check button, which runs outside any view, shares it.
    static let store = PowerJackStore(inMemory: runsInMemory)
    static var modelContainer: ModelContainer { store.container }

    // Previews and unit tests never touch the real store or iCloud.
    private static var runsInMemory: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        Hints.configure()
    }

    var body: some Scene {
        WindowGroup {
            PowerJackAppContent()
                .environment(Self.store)
        }
    }
}

/// The app's screens on the store's current container, which changes with iCloud Backup.
struct PowerJackAppContent: View {
    @Environment(PowerJackStore.self) private var store

    var body: some View {
        PowerJackRootView()
            .modelContainer(store.container)
    }
}
