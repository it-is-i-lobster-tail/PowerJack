//
//  WorkoutView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData

struct WorkoutView: View {
    let workoutExercisePreview = WorkoutExercise(
        exercise: "Bench Press",
        order: 1,
    )
    
    var body: some View {
        WorkoutExerciseView(workoutExercise: workoutExercisePreview)
    }
}

#Preview ("WorkoutView"){
    WorkoutView()
        .modelContainer(makeWorkoutExercisePreviewContainer())
}
