//
//  ProgramListView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

struct ProgramListView: View {
    @Query private var programs: [Program]

    var body: some View {
        List {
            if programs.isEmpty {
                Text("No programs")
            } else {
                ForEach(programs, id: \.self) { program in
                    VStack(alignment: .leading) {
                        Text(program.templateProgram.templateName)
                        Text(program.status.rawValue)
                            .font(.caption)
                    }
                }
            }
        }
    }
}

#Preview("ProgramListView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        ProgramListView()
    }
    .modelContainer(scenario.container)
}

#Preview("ProgramListView - Empty") {
    NavigationStack {
        ProgramListView()
    }
    .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
