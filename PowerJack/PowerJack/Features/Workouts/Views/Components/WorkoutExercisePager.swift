//
//  WorkoutExercisePager.swift
//  PowerJack
//
//  Created by Brendon on 6/26/26.
//

import SwiftUI

struct WorkoutExercisePager: View {
    let screenWidth: CGFloat
    let workoutExercises: [WorkoutExercise]
    let onExerciseSetsDone: (WorkoutExercise) -> Void
    @Binding var selectedExerciseIndex: Int?
    let focusedSetField: FocusState<FocusedSetField?>.Binding

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(workoutExercises.indices, id: \.self) { index in
                    WorkoutExerciseView(
                        onSetsDone: onExerciseSetsDone,
                        screenWidth: screenWidth,
                        focusedSetField: focusedSetField,
                        workoutExercise: workoutExercises[index]
                    )
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
            .padding(.top, LayoutMetrics.compactSpacing)
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $selectedExerciseIndex)
    }
}
