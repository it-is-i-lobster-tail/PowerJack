//
//  WorkoutActionsMenu.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftData
import SwiftUI

struct WorkoutActionsMenu: View {
    let workout: Workout
    let selectedExerciseIndex: Int?
    @Binding var isShowingWorkoutExerciseSheet: Bool
    let onEditExercise: (Exercise) -> Void
    var onSkipWorkout: (() -> Void)? = nil
    /// Opens the list of exercises and supersets the selected exercise can join.
    var onAddToSuperset: (WorkoutExercise) -> Void = { _ in }
    /// Opens the selected exercise's superset to reorder it or take exercises out.
    var onEditSuperset: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingSkipWorkout = false

    private var selectedWorkoutExercise: WorkoutExercise? {
        guard let selectedExerciseIndex,
              workout.workoutExercises.indices.contains(selectedExerciseIndex)
        else {
            return nil
        }

        return workout.workoutExercises[selectedExerciseIndex]
    }

    private var canModifySelectedExercise: Bool {
        guard let selectedWorkoutExercise else { return false }
        return !selectedWorkoutExercise.locked
    }

    private var canSkipWorkout: Bool {
        !workout.locked
    }

    var body: some View {
        Menu {
            if let selectedWorkoutExercise {
                Button {
                    isShowingWorkoutExerciseSheet.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Change Exercise")
                    }
                }
                // Changing a finished exercise would throw away its logged sets.
                .disabled(!canModifySelectedExercise || selectedWorkoutExercise.isDone)

                if let exercise = selectedWorkoutExercise.exercise {
                    Button {
                        onEditExercise(exercise)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                            Text("Edit Exercise")
                        }
                    }
                }

                // Hidden warmups come back from here, since their heading and menu are gone.
                if !selectedWorkoutExercise.showsWarmups {
                    Button {
                        withAnimation {
                            selectedWorkoutExercise.enableWarmups()
                            try? modelContext.save()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "flame")
                            Text("Enable Warmup")
                        }
                    }
                    .disabled(!canModifySelectedExercise)
                }

                if workout.canEditSupersets {
                    supersetButtons(for: selectedWorkoutExercise)
                }

                Divider()

                if selectedWorkoutExercise.canRestoreSkipped {
                    Button {
                        selectedWorkoutExercise.restoreSkipped()
                        try? modelContext.save()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Restore Exercise")
                        }
                    }
                } else {
                    Button {
                        selectedWorkoutExercise.skipRemainingSets()
                        try? modelContext.save()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "forward")
                            Text("Skip Exercise")
                        }
                    }
                    .disabled(!canModifySelectedExercise || selectedWorkoutExercise.allSetsDone())
                }

                Divider()
            }

            Button {
                isConfirmingSkipWorkout = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "forward.end")
                    Text("Skip Workout")
                }
            }
            .disabled(!canSkipWorkout)
        } label: {
            Image(systemName: "ellipsis")
        }
        .confirmationDialog(
            "Skip the rest of this workout?",
            isPresented: $isConfirmingSkipWorkout,
            titleVisibility: .visible
        ) {
            Button("Skip Workout", role: .destructive, action: skipWorkout)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sets you've finished stay logged. The rest are skipped.")
        }
    }

    /// Add to Superset for an exercise on its own. In a superset, Remove from Superset and Edit Superset instead.
    @ViewBuilder
    private func supersetButtons(for workoutExercise: WorkoutExercise) -> some View {
        if let supersetID = workoutExercise.supersetID, !workoutExercise.supersetPartners.isEmpty {
            Button {
                withAnimation {
                    workout.removeFromSuperset(workoutExercise)
                    try? modelContext.save()
                }
            } label: {
                Label("Remove from Superset", systemImage: "square.split.1x2")
            }

            Button {
                onEditSuperset(supersetID)
            } label: {
                Label("Edit Superset", systemImage: "arrow.up.arrow.down")
            }
        } else {
            Button {
                onAddToSuperset(workoutExercise)
            } label: {
                Label("Add to Superset", systemImage: "link.badge.plus")
            }
            // A finished exercise has nothing left to do in turn, and there may be nothing to join.
            .disabled(workoutExercise.isDone || workout.supersetChoices(for: workoutExercise).isEmpty)
        }
    }

    private func skipWorkout() {
        if let onSkipWorkout {
            onSkipWorkout()
        } else {
            workout.skipAndCascade()
            try? modelContext.save()
        }
    }
}
