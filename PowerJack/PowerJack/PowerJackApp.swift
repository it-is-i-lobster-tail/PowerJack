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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WorkoutSet.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            WorkoutView()
        }
        .modelContainer(sharedModelContainer)
    }
}
