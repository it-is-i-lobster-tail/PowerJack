// xcode: set sdk=iOS

//
//  PowerJackApp.swift
//  PowerJack
//
//  Created on 6/24/26.
//

import SwiftUI
import SwiftData

@main
struct PowerJackApp: App {
    /// Static so the Live Activity's check button, which runs outside any view, shares it.
    static let store: PowerJackStore = {
        #if DEBUG && targetEnvironment(simulator)
        if !runsInMemory, SimulatorTrainingHistory.isSelected {
            do {
                return try SimulatorTrainingHistory.openStore()
            } catch {
                fatalError("Could not open the sample workout history: \(error)")
            }
        }
        #endif
        return PowerJackStore(inMemory: runsInMemory)
    }()
    /// Nil while the store won't open.
    static var modelContainer: ModelContainer? { store.container }

    @UIApplicationDelegateAdaptor(PowerJackAppDelegate.self) private var appDelegate

    // Previews and unit tests never touch the real store or iCloud.
    private static var runsInMemory: Bool {
        #if DEBUG
        if WorkoutReminderDemo.enabled { return true }
        #endif
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        Hints.configure()
        #if DEBUG
        if WorkoutReminderDemo.enabled {
            WorkoutReminders.shared.start(store: Self.store)
            return
        }
        #endif
        if !Self.runsInMemory {
            WeightUnit.saveDeviceDefaultIfUnpicked()
            TraceLog.shared.start()
            TraceHooks.start()
            let store = Self.store
            if store.allowsExternalSync {
                PhoneSync.shared.start(store: store)
                WorkoutReminders.shared.start(store: store)
            }
        }
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

    @AppStorage(AppSettings.Key.appearance)
    private var appearance = AppSettings.Default.appearance

    var body: some View {
        Group {
            if let container = store.container {
                PowerJackRootView()
                    .modelContainer(container)
            } else {
                StoreUnavailableView()
            }
        }
        .windowAppearance(appearance)
        // Content fades softly under the bars instead of stopping at a hard line.
        // Sheets don't inherit this, so each one with a navigation bar sets it too.
        .scrollEdgeEffectStyle(.soft, for: .all)
    }
}
