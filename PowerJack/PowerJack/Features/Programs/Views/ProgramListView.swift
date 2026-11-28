//
//  ProgramListView.swift
//  PowerJack
//
//  Created on 7/3/26.
//

import SwiftData
import SwiftUI
import TipKit

struct ProgramListView: View {
    @Query(filter: Program.ownRows) private var programs: [Program]
    @Environment(ProgramsRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var programPendingDelete: Program?
    @State private var saveErrorMessage: String?
    /// Years the user opened or closed. Others use their default.
    @State private var expandedYears: [Int?: Bool] = [:]

    private var activeProgram: Program? {
        programs.active
    }

    private var sections: ProgramListSections<Program> {
        ProgramListSections(programs, status: \.status, startedAt: \.startedAt)
    }

    var body: some View {
        AddableListScaffold(
            navigationTitle: "My Programs",
            isEmpty: programs.isEmpty,
            emptyTitle: "No programs",
            emptySystemImage: "list.bullet.rectangle",
            hint: ProgramsHint(),
            onAdd: addProgram
        ) {
            let sections = sections
            List {
                ForEach(sections.current) { program in
                    row(for: program)
                }

                ForEach(Array(sections.past.enumerated()), id: \.offset) { index, year in
                    let isExpanded = isExpanded(year)
                    Section {
                        if isExpanded {
                            ForEach(year.items) { program in
                                row(for: program)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 12) {
                            if index == 0 {
                                Text("Past")
                                    .font(.title2.bold())
                                    .foregroundStyle(Color.primary)
                                    .padding(.top, sections.current.isEmpty ? 0 : 20)
                            }
                            yearHeader(year, isExpanded: isExpanded)
                        }
                        .textCase(nil)
                    }
                }
            }
            .listRowSpacing(10)
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            if programs.isEmpty {
                HintView(WelcomeHint())
                    .padding(.horizontal)
            }
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
            Text("Its workouts will be deleted, but your saved training history stays in Data. This can't be undone.")
        }
        .saveErrorAlert($saveErrorMessage)
    }

    private func isExpanded(_ year: ProgramListSections<Program>.Year) -> Bool {
        expandedYears[year.year] ?? year.startsExpanded()
    }

    private func yearHeader(_ year: ProgramListSections<Program>.Year, isExpanded: Bool) -> some View {
        Button {
            withAnimation {
                expandedYears[year.year] = !isExpanded
            }
        } label: {
            HStack {
                Text(year.year.map { String($0) } ?? "No workouts")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    private func row(for program: Program) -> some View {
        Button {
            select(program)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(program.templateName)
                    Text(statusText(for: program))
                        .font(.caption)
                        .foregroundStyle(program === activeProgram ? .green : .blue)
                    if program.status.isFinished, let start = program.startedAt {
                        Text(ProgramDateRange.text(from: start, to: program.endedAt))
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }

                Spacer()

                // Gray, so it reads as a label rather than part of the tappable title.
                Text(program.templateType.name)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
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

    private func delete(_ program: Program) {
        do {
            // Its sets stay in the exported history, marked deleted.
            try HistoryArchive.programWillBeDeleted(program, in: modelContext)
            program.delete()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveErrorMessage = "The program couldn't be deleted. Please try again."
        }
    }

    private func addProgram() {
        ProgramsHint().invalidate(reason: .actionPerformed)
        router.showNewProgram()
    }

    /// e.g. "In progress · 40% done" or "Finished".
    private func statusText(for program: Program) -> String {
        switch program.status {
        case .active: "In progress · \(program.percentFinished)% done"
        case .stopped, .skipped: "Stopped · \(program.percentFinished)% done"
        case .complete: "Finished"
        case .planned: "Not started"
        }
    }

    private func select(_ program: Program) {
        ProgramsHint().invalidate(reason: .actionPerformed)
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
