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
                    Text(Hint.changeExercise)
                }
                // Changing a finished exercise would throw away its logged sets.
                .disabled(!canModifySelectedExercise || selectedWorkoutExercise.isDone)

                substituteButtons(for: selectedWorkoutExercise)

                if let exercise = selectedWorkoutExercise.shownExercise {
                    Button {
                        onEditExercise(exercise)
                    } label: {
                        Label("Edit Exercise", systemImage: "pencil")
                        Text(Hint.editExercise)
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
                        Label("Turn On Warmups", systemImage: "flame")
                        Text(Hint.turnOnWarmups)
                    }
                    .disabled(!canModifySelectedExercise)
                }

                if workout.canEditSupersets {
                    supersetButton(for: selectedWorkoutExercise)
                }

                Divider()

                if selectedWorkoutExercise.canRestoreSkipped {
                    Button {
                        selectedWorkoutExercise.restoreSkipped()
                        modelContext.saveTraced("exercise restored")
                    } label: {
                        Label("Restore Exercise", systemImage: "arrow.counterclockwise")
                        Text(Hint.restoreExercise)
                    }
                } else {
                    Button {
                        selectedWorkoutExercise.skipRemainingSets()
                        modelContext.saveTraced("exercise skipped")
                    } label: {
                        Label("Skip Exercise", systemImage: "forward")
                        Text(Hint.skipExercise)
                    }
                    .disabled(!canModifySelectedExercise || selectedWorkoutExercise.allSetsDone())
                }

                Divider()
            }

            Button {
                isConfirmingSkipWorkout = true
            } label: {
                Label("Skip Workout", systemImage: "forward.end")
                Text(Hint.skipWorkout)
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
                Text(Hint.substitute)
            }

            if workoutExercise.substitute != nil {
                Button {
                    workoutExercise.undoSubstitute()
                    modelContext.saveTraced("substitute undone")
                } label: {
                    Label("Undo Substitute", systemImage: "arrow.uturn.backward")
                    Text(Hint.undoSubstitute)
                }
            }
        }
    }

    @ViewBuilder
    private func supersetButton(for workoutExercise: WorkoutExercise) -> some View {
        if let supersetID = workoutExercise.supersetID, !workoutExercise.supersetPartners.isEmpty {
            Button {
                onEditSuperset(supersetID)
            } label: {
                Label("Edit Superset", systemImage: "arrow.up.arrow.down")
                Text(Hint.editSuperset)
            }
        } else {
            Button {
                onAddToSuperset(workoutExercise)
            } label: {
                Label("Add to Superset", systemImage: "link.badge.plus")
                Text(Hint.addToSuperset)
            }
            // A finished exercise has nothing left to do in turn, and there may be nothing to join.
            .disabled(workoutExercise.isDone || workout.supersetChoices(for: workoutExercise).isEmpty)
        }
    }

    /// The short line under each menu item. Each stays within `Hint.maxLength` characters so the
    /// menu shows it in full, never cut off with "…".
    enum Hint {
        static let maxLength = 24

        static let changeExercise = "Replaces it from now on"
        static let substitute = "Only for this workout"
        static let undoSubstitute = "Back to the original"
        static let editExercise = "Rep range, rest and more"
        static let turnOnWarmups = "Adds warmup sets back"
        static let addToSuperset = "Start or join a superset"
        static let editSuperset = "Reorder or remove"
        static let skipExercise = "Skips its remaining sets"
        static let restoreExercise = "Brings back its sets"
        static let skipWorkout = "Ends this workout early"

        static let all = [
            changeExercise, substitute, undoSubstitute, editExercise, turnOnWarmups, addToSuperset,
            editSuperset, skipExercise, restoreExercise, skipWorkout,
        ]
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
