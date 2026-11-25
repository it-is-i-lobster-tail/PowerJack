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
    @State private var index: ExerciseChartSearch.Index?
    @State private var searchText = ""
    @State private var muscles: Set<Muscle> = []
    @State private var exerciseToEdit: Exercise?
    @State private var isCreating = false
    @State private var isFiltering = false

    init(navigationTitle: String, mode: ExercisePickerMode = .add, onSelect: ((Exercise) -> Void)? = nil) {
        self.navigationTitle = navigationTitle
        self.mode = mode
        self.onSelect = onSelect
    }

    var body: some View {
        let results = ExercisePickerResults(exercises: exercises, index: index, query: searchText, muscles: muscles, mode: mode)
        NavigationStack {
            List {
                if !results.suggested.isEmpty {
                    Section("Suggested") {
                        ForEach(results.suggested) { exercise in row(exercise) }
                    }
                }
                if !results.named.isEmpty {
                    Section {
                        ForEach(results.named) { exercise in row(exercise) }
                    } header: {
                        if !results.suggested.isEmpty { Text("Exercises") }
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
            .navigationDestination(item: $exerciseToEdit) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
            .navigationDestination(isPresented: $isCreating) {
                ExerciseNewView(name: results.isEmpty ? searchText : "", onSave: handleNewExercise)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if mode.isSubstitution {
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
                if !mode.isSubstitution {
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
        .background { ExerciseSearchIndexLoader(index: $index) }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .traceScreen(mode.isSubstitution ? "Substitute Picker" : "Exercise Picker")
    }

    @ViewBuilder
    private func row(_ exercise: Exercise) -> some View {
        if case .substitute(let workoutExercise) = mode {
            ExerciseSelectionRow(exercise: exercise, isSelected: exercise === workoutExercise.substitute) {
                selectOrEdit(exercise)
            }
            .buttonStyle(.plain)
        } else {
            ExerciseSelectionRow(exercise: exercise) { selectOrEdit(exercise) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Edit", systemImage: "pencil") { edit(exercise) }
                        .tint(.blue)
                }
        }
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
