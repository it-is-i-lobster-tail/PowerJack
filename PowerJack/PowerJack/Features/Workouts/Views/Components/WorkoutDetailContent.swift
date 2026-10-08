//
//  WorkoutDetailContent.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct WorkoutDetailContent: View {
    let screenWidth: CGFloat
    let workoutExercises: [WorkoutExercise]
    @Binding var selectedExerciseIndex: Int?
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    let onExerciseSetsDone: (WorkoutExercise) -> Void

    var body: some View {
        // The sets take every point the exercise strip doesn't need, less a gap above the strip.
        VStack(spacing: LayoutMetrics.compactSpacing) {
            WorkoutExercisePager(
                screenWidth: screenWidth,
                workoutExercises: workoutExercises,
                onExerciseSetsDone: onExerciseSetsDone,
                selectedExerciseIndex: $selectedExerciseIndex,
                focusedSetField: focusedSetField
            )
            .frame(maxHeight: .infinity)

            ExercisePreviewStrip(
                workoutExercises: workoutExercises,
                screenWidth: screenWidth,
                selectedExerciseIndex: $selectedExerciseIndex
            )
        }
        .frame(width: screenWidth)
    }
}
