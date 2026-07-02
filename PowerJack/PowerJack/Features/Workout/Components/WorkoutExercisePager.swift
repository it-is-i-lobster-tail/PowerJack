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
    @Binding var selectedExerciseIndex: Int?
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(workoutExercises.indices, id: \.self) { index in
                    WorkoutExerciseView(
                        screenWidth: screenWidth,
                        workoutExercise: workoutExercises[index],
                        focusedSetField: focusedSetField
                    )
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
            .padding(.top, 40)
        }
        .frame(height: 620)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $selectedExerciseIndex)
    }
}
