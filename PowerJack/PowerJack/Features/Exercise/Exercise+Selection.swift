//
//  Workout+Exercise.swift
//  PowerJack
//
//  Created by Brendon on 7/4/26.
//

import SwiftUI
import SwiftData

struct ExerciseSelection: View {
    let workoutExerciseToChange: WorkoutExercise?
    let navigationTitle: String
    
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.exerciseName) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var showNewExerciseView = false
    @State private var showExerciseDetailView = false
    @State private var exercisetoEdit: Exercise?
    
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
    
    private func handleNewExercise(newExercise: Exercise) {
        workoutExerciseToChange?.changeExercise(newExercise: newExercise)
        dismiss()
    }
    private func handleUpdateExercise(updateExercise: Exercise) {
        showExerciseDetailView = false
    }

    var body: some View {
        NavigationStack {
            List(filteredExercises) { exercise in
                Button {
                    handleNewExercise(newExercise: exercise)
                } label: {
                    HStack {
                    VStack(alignment: .leading) {
                        Text(exercise.exerciseName)
                        HStack {
                            Text(exercise.exerciseEquipment.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("|")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(exercise.primaryMuscleFocus.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        }
                    Spacer()
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        exercisetoEdit = exercise
                        showExerciseDetailView = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                    
                }
            }
            .navigationTitle(navigationTitle)
            .searchable(text: $searchText, prompt: "Search exercises")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showNewExerciseView) {
                ExerciseNew(onSave: handleNewExercise)
            }
            .navigationDestination(isPresented: $showExerciseDetailView) {
                if let exercisetoEdit {
                    ExerciseDetailView(
                        exercise: exercisetoEdit,
                        onSave: handleUpdateExercise
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.left")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewExerciseView = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

#Preview("ExerciseSelection - Change Exercise") {
    let scenario = PowerJackSeed.weekOneProgress()

    ExerciseSelection(
        workoutExerciseToChange: scenario.weekOneWorkouts[2].workoutExercises[0],
        navigationTitle: "Change Exercise"
    )
    .modelContainer(scenario.container)
}

#Preview("ExerciseSelection - Browse Only") {
    let scenario = PowerJackSeed.weekOneProgress()

    ExerciseSelection(
        workoutExerciseToChange: nil,
        navigationTitle: "Select Exercise"
    )
    .modelContainer(scenario.container)
}

#Preview("ExerciseSelection - Empty") {
    ExerciseSelection(
        workoutExerciseToChange: nil,
        navigationTitle: "Select Exercise"
    )
    .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
