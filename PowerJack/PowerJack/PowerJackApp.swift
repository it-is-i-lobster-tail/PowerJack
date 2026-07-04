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
    private let seedScenario = PowerJackSeed.weekOneProgress()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ProgramDetailView(program: seedScenario.program)
            }
        }
        .modelContainer(seedScenario.container)
    }
}
