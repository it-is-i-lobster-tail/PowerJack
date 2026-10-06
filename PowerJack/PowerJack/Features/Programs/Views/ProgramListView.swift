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
    @Environment(ProgramsRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var programPendingDelete: Program?
    @State private var saveErrorMessage: String?

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
            emptySystemImage: "list.bullet.rectangle",
            onAdd: router.showNewProgram
        ) {
            List(displayedPrograms) { program in
                Button {
                    select(program)
                } label: {
                    VStack(alignment: .leading) {
                        Text(program.templateName)
                        Text("\(program.status.rawValue)  |  \(program.percentFinished)%")
                            .font(.caption)
                            .foregroundStyle(program === activeProgram ? .green : .blue)
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // No destructive role: it removes the row before the user confirms.
                    Button {
                        programPendingDelete = program
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(program.status == .active ? .gray : .red)
                    .disabled(program.status == .active)
                }
            }
            .listRowSpacing(10)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
        }
        .alert(
            "Delete “\(programPendingDelete?.templateName ?? "")”?",
            isPresented: Binding(
                get: { programPendingDelete != nil },
                set: { if !$0 { programPendingDelete = nil } }
            ),
            presenting: programPendingDelete
        ) { program in
            Button("Delete", role: .destructive) {
                delete(program)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its workouts will be deleted, but your training history stays in Volume. This can't be undone.")
        }
        .saveErrorAlert($saveErrorMessage)
    }

    private func delete(_ program: Program) {
        program.delete()
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveErrorMessage = "The program couldn't be deleted. Please try again."
        }
    }

    private func select(_ program: Program) {
        router.showDetail(program)
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
