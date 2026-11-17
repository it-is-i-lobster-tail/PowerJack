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
                    Label("Change Exercise", systemImage: "slider.horizontal.3")
                    Text("Replaces this exercise on this day from now on. Your template stays the same.")
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
                            modelContext.saveTraced("warmups turned on")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "flame")
                            Text("Turn On Warmups")
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
                        modelContext.saveTraced("exercise restored")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Restore Exercise")
                        }
                    }
                } else {
                    Button {
                        selectedWorkoutExercise.skipRemainingSets()
                        modelContext.saveTraced("exercise skipped")
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
                    modelContext.saveTraced("substitute picked")
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
                Label("One-Time Substitute", systemImage: "arrow.triangle.swap")
                Text("Just this workout")
            }

            if workoutExercise.substitute != nil {
                Button {
                    workoutExercise.undoSubstitute()
                    modelContext.saveTraced("substitute undone")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Undo Substitute")
                    }
                }
            }
        }
    }

    /// Add to Superset for an exercise on its own. In a superset, Remove from Superset and Edit Superset instead.
    @ViewBuilder
    private func supersetButtons(for workoutExercise: WorkoutExercise) -> some View {
        if let supersetID = workoutExercise.supersetID, !workoutExercise.supersetPartners.isEmpty {
            Button {
                withAnimation {
                    workout.removeFromSuperset(workoutExercise)
                    modelContext.saveTraced("removed from superset")
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
            modelContext.saveTraced("workout skipped")
        }
    }
}
