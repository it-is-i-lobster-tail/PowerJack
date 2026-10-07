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
                .disabled(!canModifySelectedExercise)

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

                Divider()

                Button {
                    selectedWorkoutExercise.skipAndCascade()
                    try? modelContext.save()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "forward")
                        Text("Skip Remaining Sets")
                    }
                }
                .disabled(!canModifySelectedExercise)
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
