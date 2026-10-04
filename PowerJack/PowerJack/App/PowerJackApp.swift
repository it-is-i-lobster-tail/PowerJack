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

    var body: some Scene {
        WindowGroup {
            PowerJackRootView()
                // Switching iCloud Backup replaces the container, so rebuild every screen from it.
                .id(ObjectIdentifier(Self.store.container))
                .modelContainer(Self.store.container)
                .environment(Self.store)
        }
    }
}
