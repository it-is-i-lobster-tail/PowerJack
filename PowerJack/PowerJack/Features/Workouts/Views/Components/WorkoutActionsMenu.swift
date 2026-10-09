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

                Divider()

                Button {
                    selectedWorkoutExercise.skipRemainingSets()
                    try? modelContext.save()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "forward")
                        Text("Skip Remaining Sets")
                    }
                }
                .disabled(!canModifySelectedExercise || selectedWorkoutExercise.allSetsDone())
            }

            Button {
                if let onSkipWorkout {
                    onSkipWorkout()
                } else {
                    workout.skipAndCascade()
                    try? modelContext.save()
                }
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
    }
}
