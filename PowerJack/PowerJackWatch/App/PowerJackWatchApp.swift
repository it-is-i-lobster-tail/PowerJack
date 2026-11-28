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
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: WatchStore
    @State private var sync: WatchSync

    init() {
        TraceLog.shared.start()
        let store = WatchStore()
        _store = State(initialValue: store)
        _sync = State(initialValue: WatchSync(store: store))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // Switching iCloud Backup replaces the container. The screens holding its models
                // come down first, then the new container opens and they rebuild from it.
                if store.isReplacingContainer {
                    Color.black
                        .ignoresSafeArea()
                        .onAppear { store.replaceContainer() }
                } else if let container = store.container {
                    WatchRootView()
                        .id(ObjectIdentifier(container))
                        .modelContainer(container)
                } else {
                    WatchStoreUnavailableView()
                }
            }
            // The iPhone's accent: system blue.
            .tint(.blue)
            .environment(store)
            .environment(sync)
        }
        .onChange(of: scenePhase, initial: true) {
            // A store that didn't open, say before the first unlock, gets another go.
            if scenePhase == .active { store.retryOpening() }
            // Opening the app catches up with the iPhone: what's pending goes, its program comes back.
            if scenePhase == .active { sync.push() }
            // The iPhone's trace export includes the watch's, as of when it last left the screen.
            if scenePhase == .background { Task { await DeviceLink.shared.sendTrace() } }
        }
    }
}
