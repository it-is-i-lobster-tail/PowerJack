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
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
        } createDestination: {
            ProgramNew(onSave: handleNewProgram)
        }
        .navigationDestination(item: $selectedProgram) { program in
            ProgramDetailView(program: program)
        }
    }

    private func select(_ program: Program) {
        selectedProgram = program
    }

    private func handleNewProgram(newProgram: Program) {
        if let activeProgram {
            activeProgram.stop()
            activeProgram.stopAndCascade()
        }
        newProgram.start()
    }
}

#Preview("ProgramListView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ProgramListView()
    }
}

#Preview("ProgramListView - Empty") {
    NavigationPreviewHost(modelContainer: PowerJackSeed.makeInMemoryContainer()) {
        ProgramListView()
    }
}
