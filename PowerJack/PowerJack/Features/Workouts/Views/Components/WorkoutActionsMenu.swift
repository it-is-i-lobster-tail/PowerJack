//
//  WorkoutActionsMenu.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct WorkoutActionsMenu: View {
    let workout: Workout
    let selectedExerciseIndex: Int?
    @Binding var isShowingWorkoutExerciseSheet: Bool

    private var selectedWorkoutExercise: WorkoutExercise? {
        guard let selectedExerciseIndex,
              workout.workoutExercises.indices.contains(selectedExerciseIndex)
        else {
            return nil
        }

        return workout.workoutExercises[selectedExerciseIndex]
    }

    private var canAddSet: Bool {
        guard let selectedWorkoutExercise else { return false }

        return selectedWorkoutExercise.totalSets < WorkoutExercise.maxSets &&
            !selectedWorkoutExercise.locked
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
                    _ = selectedWorkoutExercise.addSet()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Set")
                    }
                }
                .disabled(!canAddSet)

                Button {
                    isShowingWorkoutExerciseSheet.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Change Exercise")
                    }
                }
                .disabled(!canModifySelectedExercise)

                Button {
                    _ = selectedWorkoutExercise.removeLastSet()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Remove Last Set")
                    }
                }
                .disabled(!canModifySelectedExercise)

                Divider()

                Button {
                    selectedWorkoutExercise.skipAndCascade()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "forward")
                        Text("Skip Remaining Sets")
                    }
                }
                .disabled(!canModifySelectedExercise)
            }

            Button {
                workout.skipAndCascade()
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
