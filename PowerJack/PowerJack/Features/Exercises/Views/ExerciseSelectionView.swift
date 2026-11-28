//
//  ExerciseSelectionView.swift
//  PowerJack
//
//  Created on 7/4/26.
//

import SwiftData
import SwiftUI

struct ExerciseSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let navigationTitle: String
    let mode: ExercisePickerMode
    let onSelect: ((Exercise) -> Void)?

    @Query private var exercises: [Exercise]
    @State private var index: ExerciseSearch.Index?
    @State private var familiarity = ExerciseFamiliarity.none
    @State private var searchText = ""
    @State private var muscles: Set<Muscle> = []
    @State private var exerciseToEdit: Exercise?
    @State private var isCreating = false
    @State private var isFiltering = false
    /// The on-device model's reading of a long search, and the text it read.
    @State private var reading: ExerciseFilters?
    @State private var readText = ""

    init(navigationTitle: String, mode: ExercisePickerMode = .add, onSelect: ((Exercise) -> Void)? = nil) {
        self.navigationTitle = navigationTitle
        self.mode = mode
        self.onSelect = onSelect
    }

    var body: some View {
        let typed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Typing on drops the reading, so the fast results return.
        let filters = readText == typed ? reading : nil
        let results = ExercisePickerResults(exercises: exercises, index: index, familiarity: familiarity,
                                            query: searchText, filters: filters, muscles: muscles, mode: mode)
        NavigationStack {
            List {
                if let filters {
                    Section {
                        HStack {
                            Text("Showing: \(filters.summary)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Show All Matches", systemImage: "xmark.circle.fill") { reading = nil }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                                .buttonStyle(.borderless)
                        }
                    }
                }
                Section {
                    ForEach(results.matches) { exercise in row(exercise) }
                    if !typed.isEmpty && !mode.picksExisting {
                        Button("Add \u{201C}\(typed)\u{201D}", systemImage: "plus") { isCreating = true }
                    }
                }
                if !results.others.isEmpty {
                    Section("All Exercises") {
                        ForEach(results.others) { exercise in row(exercise) }
                    }
                }
            }
            .overlay {
                if results.isEmpty {
                    if index == nil && !searchText.isEmpty {
                        ProgressView("Preparing search")
                    } else {
                        EmptyStateView(title: searchText.isEmpty && muscles.isEmpty ? "No exercises" : "No matching exercises",
                                       systemImage: "magnifyingglass")
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search exercises")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onSubmit(of: .search) {
                guard results.isThin else { return }
                Task { await read(typed) }
            }
            .onChange(of: typed.split(separator: " ").count >= 3) { _, isLong in
                if isLong { ExerciseQueryModel.shared.prewarm() }
            }
            .navigationDestination(item: $exerciseToEdit) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
            .navigationDestination(isPresented: $isCreating) {
                ExerciseNewView(name: typed, onSave: handleNewExercise)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if mode.picksExisting {
                        Button("Cancel", action: dismiss.callAsFunction)
                    } else {
                        Button("Close", systemImage: "arrow.left", action: dismiss.callAsFunction)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Filter", systemImage: muscles.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") {
                        isFiltering = true
                    }
                    .accessibilityValue(muscles.isEmpty ? "All muscles" : "\(muscles.count) selected")
                }
                if !mode.picksExisting {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add", systemImage: "plus") { isCreating = true }
                    }
                }
            }
        }
        .sheet(isPresented: $isFiltering) {
            NavigationStack {
                List {
                    FilterOptions("All muscles", choices: Muscle.allCases.sorted { $0.rawValue < $1.rawValue },
                                  selected: $muscles, title: { $0.rawValue.capitalized })
                }
                .navigationTitle("Filter")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isFiltering = false }
                    }
                }
            }
        }
        .background { ExerciseSearchIndexLoader(index: $index, familiarity: $familiarity) }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .traceScreen(traceName)
    }

    @ViewBuilder
    private func row(_ exercise: Exercise) -> some View {
        if case .substitute(let workoutExercise) = mode {
            ExerciseSelectionRow(exercise: exercise, isSelected: exercise === workoutExercise.substitute) {
                selectOrEdit(exercise)
            }
            .buttonStyle(.plain)
        } else if mode.picksExisting {
            ExerciseSelectionRow(exercise: exercise) { selectOrEdit(exercise) }
                .buttonStyle(.plain)
        } else {
            ExerciseSelectionRow(exercise: exercise) { selectOrEdit(exercise) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Edit", systemImage: "pencil") { edit(exercise) }
                        .tint(.blue)
                }
        }
    }

    private var traceName: String {
        switch mode {
        case .substitute: "Substitute Picker"
        case .merge: "Merge Picker"
        case .add, .change: "Exercise Picker"
        }
    }

    /// Fast results stay on screen while the model reads the search.
    private func read(_ text: String) async {
        guard let found = await ExerciseQueryModel.shared.filters(for: text),
              searchText.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
        readText = text
        reading = found
    }

    private func selectOrEdit(_ exercise: Exercise) {
        guard let onSelect else {
            edit(exercise)
            return
        }

        onSelect(exercise)
        dismiss()
    }

    private func handleNewExercise(_ exercise: Exercise) {
        guard let onSelect else { return }
        onSelect(exercise)
        dismiss()
    }

    private func edit(_ exercise: Exercise) {
        exerciseToEdit = exercise
    }
}

#Preview("ExerciseSelection - Change Exercise") {
    let scenario = PowerJackSeed.weekOneProgress()

    ExerciseSelectionView(
        navigationTitle: "Change Exercise",
        mode: .change(scenario.weekOneWorkouts[2].workoutExercises[0].exercise),
        onSelect: { exercise in
            scenario.weekOneWorkouts[2].workoutExercises[0]
                .changeExercise(newExercise: exercise)
        }
    )
    .modelContainer(scenario.container)
}

#Preview("ExerciseSelection - Browse Only") {
    let scenario = PowerJackSeed.weekOneProgress()

    ExerciseSelectionView(
        navigationTitle: "Select Exercise"
    )
    .modelContainer(scenario.container)
}

#Preview("ExerciseSelection - Empty") {
    ExerciseSelectionView(
        navigationTitle: "Select Exercise"
    )
    .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
