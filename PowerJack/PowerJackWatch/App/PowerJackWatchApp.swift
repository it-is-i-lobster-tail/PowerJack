//
//  PowerJackWatchApp.swift
//  PowerJackWatch
//
//  Runs the current workout of the program started on the iPhone. The program comes straight from
//  the iPhone when it's nearby and through iCloud otherwise, so the watch works without the iPhone
//  nearby, and it plans the next week itself.
//

import SwiftData
import SwiftUI

@main
struct PowerJackWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: WatchStore
    @State private var sync: WatchSync

    init() {
        let store = WatchStore()
        _store = State(initialValue: store)
        _sync = State(initialValue: WatchSync(store: store))
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                // The iPhone's accent: system blue.
                .tint(.blue)
                .environment(store)
                .environment(sync)
                .modelContainer(store.container)
        }
        .onChange(of: scenePhase, initial: true) {
            // Opening the app catches up with the iPhone: what's pending goes, its program comes back.
            if scenePhase == .active { sync.push() }
        }
    }
}
