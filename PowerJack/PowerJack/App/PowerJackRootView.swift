//
//  PowerJackRootView.swift
//  PowerJack
//
//  Created by Codex on 7/17/26.
//

import SwiftData
import SwiftUI

struct PowerJackRootView: View {
    @Query private var programs: [Program]

    private var activeProgram: Program? { programs.active }

    var body: some View {
        NavigationStack {
            Group {
                if let activeProgram {
                    ProgramDetailView(program: activeProgram)
                } else {
                    ProgramListView()
                }
            }
        }
    }
}

#Preview("PowerJackRootView - Active Program") {
    let scenario = PowerJackSeed.weekOneProgress()

    PowerJackRootView()
        .modelContainer(scenario.container)
}

#Preview("PowerJackRootView - No Active Program") {
    PowerJackRootView()
        .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
