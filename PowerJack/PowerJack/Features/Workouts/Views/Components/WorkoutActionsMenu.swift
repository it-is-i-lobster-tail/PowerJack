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

    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingSkipWorkout = false
    @State private var isPickingSubstitute = false

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

                substituteButtons(for: selectedWorkoutExercise)

                if let exercise = selectedWorkoutExercise.shownExercise {
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
        .sheet(isPresented: $isPickingSubstitute) {
            if let selectedWorkoutExercise {
                SubstitutePicker(workoutExercise: selectedWorkoutExercise) { exercise in
                    selectedWorkoutExercise.substitute(with: exercise)
                    try? modelContext.save()
                }
            }
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

    /// One-Time Substitute swaps the exercise for this workout only, until a working set is logged.
    @ViewBuilder
    private func substituteButtons(for workoutExercise: WorkoutExercise) -> some View {
        if workoutExercise.canSubstitute {
            Button {
                isPickingSubstitute = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.swap")
                    Text("One-Time Substitute")
                }
            }

            if workoutExercise.substitute != nil {
                Button {
                    workoutExercise.undoSubstitute()
                    try? modelContext.save()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Undo Substitute")
                    }
                }
            }
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
