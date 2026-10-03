//
//  WorkoutExerciseView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftData
import SwiftUI

struct WorkoutExerciseView: View {
    let onSetsDone: (WorkoutExercise) -> Void
    let screenWidth: CGFloat
    let focusedSetField: FocusState<FocusedSetField?>.Binding

    @Bindable var workoutExercise: WorkoutExercise

    var body: some View {
        VStack {
            VStack(alignment: .center) {
                Text(workoutExercise.exercise.exerciseName)
                    .font(.title)
                    .foregroundStyle(.primary)
                Text(workoutExercise.exercise.exerciseEquipment.rawValue.localizedCapitalized)
                    .font(.default)
                    .foregroundStyle(.primary)
                if workoutExercise.checkInPending {
                    Label("Check-in required", systemImage: "cross.case")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            List(Array(workoutExercise.workoutSets.enumerated()), id: \.element.id) { index, workoutSet in

                VStack {
                    WorkoutSetView(
                        focusedSetField: focusedSetField,
                        workoutSet: workoutSet,
                        repsOnly: workoutExercise.exercise.repsOnly,
                        onWeightChange: { weight in
                            workoutExercise.applyWeight(weight, after: workoutSet)
                        },
                        // A finished set closes the keyboard; the next set waits for a tap.
                        onAutoComplete: { focusedSetField.wrappedValue = nil }
                    )
                    .frame(width: screenWidth * 0.88, height: 55)

                    if index < (workoutExercise.workoutSets.count - 1) {
                        Color.gray.opacity(0.2)
                            .frame(width: screenWidth * 0.75, height: 1)
                            .padding(.bottom, LayoutMetrics.compactSpacing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
            .listRowSpacing(0)
        }
        .onChange(of: workoutExercise.allSetsDone()) { wasDone, isDone in
            guard !wasDone, isDone else { return }
            focusedSetField.wrappedValue = nil
            onSetsDone(workoutExercise)
        }
    }
}
