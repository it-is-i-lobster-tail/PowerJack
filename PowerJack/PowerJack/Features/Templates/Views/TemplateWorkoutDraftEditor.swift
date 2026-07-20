//
//  TemplateWorkoutDraftEditor.swift
//  PowerJack
//
//  Created by Codex on 7/20/26.
//

import SwiftUI

struct TemplateWorkoutDraftEditor: View {
    let dayNumber: Int

    @Binding var draft: TemplateWorkoutDraft
    @State private var isSelectingExercise = false

    var body: some View {
        List {
            ForEach(draft.templateExerciseDrafts) { exerciseDraft in
                if let exercise = exerciseDraft.exercise {
                    VStack(alignment: .leading) {
                        Text(exercise.exerciseName)
                        Text(exercise.primaryMuscleFocus.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: removeExercises)
            .onMove(perform: moveExercises)
        }
        .navigationTitle("Day \(dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if draft.templateExerciseDrafts.isEmpty {
                EmptyStateView(
                    title: "No exercises",
                    systemImage: "dumbbell"
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: presentExerciseSelection) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Exercise")
            }
        }
        .sheet(isPresented: $isSelectingExercise) {
            ExerciseSelectionView(
                navigationTitle: "Add Exercise",
                isExerciseEnabled: { exercise in
                    !draft.contains(exercise)
                },
                onSelect: addExercise
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func presentExerciseSelection() {
        isSelectingExercise = true
    }

    private func addExercise(_ exercise: Exercise) {
        draft.addTemplateExerciseDraft(exercise: exercise)
    }

    private func removeExercises(at offsets: IndexSet) {
        draft.removeTemplateExercises(at: offsets)
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        draft.moveTemplateExercises(from: source, to: destination)
    }
}
