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
    private let modelContainer: ModelContainer = {
        do {
            let container = try PowerJackSchema.makeModelContainer(
                inMemory: ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            )
            try ExerciseCatalog.seed(in: container.mainContext)
            try TemplateCatalog.seed(in: container.mainContext)
            return container
        } catch {
            fatalError("Could not create PowerJack's model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            PowerJackRootView()
        }
        .modelContainer(modelContainer)
    }
}
