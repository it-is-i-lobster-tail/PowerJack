//
//  WorkoutDetailContent.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct WorkoutDetailContent: View {
    let screenWidth: CGFloat
    let contentHeight: CGFloat
    let workoutExercises: [WorkoutExercise]
    @Binding var selectedExerciseIndex: Int?
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    let nextWorkoutExercise: () -> Void

    var body: some View {
        ZStack {
            VStack {
                WorkoutExercisePager(
                    screenWidth: screenWidth,
                    workoutExercises: workoutExercises ,
                    nextWorkoutExercise: nextWorkoutExercise,
                    selectedExerciseIndex: $selectedExerciseIndex,
                    focusedSetField: focusedSetField
                )
                .frame(
                    width: screenWidth,
                    height: contentHeight * 0.85
                )

                ExercisePreviewStrip(
                    workoutExercises: workoutExercises,
                    screenWidth: screenWidth,
                    selectedExerciseIndex: $selectedExerciseIndex
                )
                .frame(
                    width: screenWidth,
                    height: contentHeight * 0.1
                )
            }
        }
    }
}
