//
//  ExerciseSelectionView.swift
//  PowerJack
//
//  Created by Brendon on 7/4/26.
//

import SwiftData
import SwiftUI

struct ExerciseSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let navigationTitle: String
    let isExerciseEnabled: (Exercise) -> Bool
    let onSelect: ((Exercise) -> Void)?

    @Query(sort: \Exercise.exerciseName) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var exerciseToEdit: Exercise?

    private var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises
        }

        return exercises.filter {
            $0.exerciseName.localizedStandardContains(searchText) ||
            $0.exerciseEquipment.rawValue.localizedStandardContains(searchText) ||
            $0.primaryMuscleFocus.rawValue.localizedStandardContains(searchText)
        }
    }

    private var emptyTitle: LocalizedStringKey {
        searchText.isEmpty ? "No exercises" : "No matching exercises"
    }

    private var emptySystemImage: String {
        searchText.isEmpty ? "dumbbell" : "magnifyingglass"
    }

    init(
        navigationTitle: String,
        isExerciseEnabled: @escaping (Exercise) -> Bool = { _ in true },
        onSelect: ((Exercise) -> Void)? = nil
    ) {
        self.navigationTitle = navigationTitle
        self.isExerciseEnabled = isExerciseEnabled
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            AddableListScaffold(
                navigationTitle: LocalizedStringKey(navigationTitle),
                isEmpty: filteredExercises.isEmpty,
                emptyTitle: emptyTitle,
                emptySystemImage: emptySystemImage
            ) {
                List(filteredExercises) { exercise in
                    ExerciseSelectionRow(
                        exercise: exercise,
                        isEnabled: isExerciseEnabled(exercise),
                        onSelect: { selectOrEdit(exercise) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            edit(exercise)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            } createDestination: {
                ExerciseNewView(onSave: handleNewExercise)
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationDestination(item: $exerciseToEdit) { exercise in
                ExerciseDetailView(
                    exercise: exercise,
                    onSave: handleUpdateExercise
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "arrow.left")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private func selectOrEdit(_ exercise: Exercise) {
        guard isExerciseEnabled(exercise) else { return }

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

    private func handleUpdateExercise(_: Exercise) {
        exerciseToEdit = nil
    }

    private func edit(_ exercise: Exercise) {
        exerciseToEdit = exercise
    }
}

#Preview("ExerciseSelection - Change Exercise") {
    let scenario = PowerJackSeed.weekOneProgress()

    ExerciseSelectionView(
        navigationTitle: "Change Exercise",
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
