//
//  WorkoutExerciseView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI

struct WorkoutExerciseView: View {
    let nextWorkoutExercise: () -> Void
    let screenWidth: CGFloat
    let focusedSetField: FocusState<FocusedSetField?>.Binding

    @Bindable var workoutExercise: WorkoutExercise
    @State private var isShowingFeedbackSheet = false

    var body: some View {
        VStack {
            VStack(alignment: .center) {
                Text(workoutExercise.exercise.exerciseName)
                    .font(.title)
                    .foregroundStyle(.primary)
                Text(workoutExercise.exercise.exerciseEquipment.rawValue.localizedCapitalized)
                    .font(.default)
                    .foregroundStyle(.primary)
            }
            List(Array(workoutExercise.workoutSets.enumerated()), id: \.element.id) { index, workoutSet in

                VStack {
                    WorkoutSetView(
                        focusedSetField: focusedSetField,
                        workoutSet: workoutSet
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
            showFeedbackIfNeeded(wasDone: wasDone, isDone: isDone)
        }
        .sheet(isPresented: $isShowingFeedbackSheet) {
            Feedback(
                nextWorkoutExercise: nextWorkoutExercise,
                workoutExercise: workoutExercise
            )
                .padding(.horizontal, LayoutMetrics.sectionSpacing)
                .interactiveDismissDisabled()
                .presentationDragIndicator(.hidden)
        }
    }

    private func showFeedbackIfNeeded(wasDone: Bool, isDone: Bool) {
        guard !wasDone, isDone else {
            return
        }

        focusedSetField.wrappedValue = nil
        isShowingFeedbackSheet = true
    }
}
