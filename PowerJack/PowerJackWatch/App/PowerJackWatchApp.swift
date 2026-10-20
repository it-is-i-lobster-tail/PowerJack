//
//  PowerJackWatchApp.swift
//  PowerJackWatch
//
//  Runs the current workout of the program started on the iPhone. Workouts sync through iCloud,
//  so the watch works without the iPhone nearby, and it plans the next week itself.
//

import SwiftData
import SwiftUI

@main
struct PowerJackWatchApp: App {
    @State private var store = WatchStore()

    init() {
        SettingsSync.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                // The iPhone's accent: system blue.
                .tint(.blue)
                .environment(store)
                .modelContainer(store.container)
        }
    }
}
