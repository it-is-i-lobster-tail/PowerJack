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

    @State private var selectedProgram: Program?

    private var activeProgram: Program? {
        programs.active
    }

    private var displayedPrograms: [Program] {
        var result = programs

        guard let activeProgram else {
            return result
        }

        guard let activeIndex = result.firstIndex(where: {
            $0 === activeProgram
        }) else {
            return result
        }

        let active = result.remove(at: activeIndex)
        result.insert(active, at: result.startIndex)

        return result
    }

    var body: some View {
        AddableListScaffold(
            navigationTitle: "My Programs",
            isEmpty: programs.isEmpty,
            emptyTitle: "No programs",
            emptySystemImage: "list.bullet.rectangle"
        ) {
            List(displayedPrograms) { program in
                Button {
                    select(program)
                } label: {
                    VStack(alignment: .leading) {
                        Text(program.templateProgram.templateName)
                        Text("\(program.status.rawValue)  |  \(program.percentFinished)%")
                            .font(.caption)
                            .foregroundStyle(program === activeProgram ? .green : .blue)
                    }
                }
            }
        } createDestination: {
            ProgramNew(onSave: handleNewProgram)
        }
        .navigationDestination(item: $selectedProgram) { program in
            ProgramDetailView(program: program)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    TemplateProgramListView()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Templates")
            }
        }
    }

    private func select(_ program: Program) {
        selectedProgram = program
    }

    private func handleNewProgram(_: Program) {}
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
