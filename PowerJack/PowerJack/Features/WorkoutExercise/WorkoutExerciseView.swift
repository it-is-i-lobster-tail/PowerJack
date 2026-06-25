//
//  LiftView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData

struct WorkoutExerciseView: View {
    @Bindable var workoutExercise: WorkoutExercise
    
    var body: some View {
        Text("Lift")
            .font(.title)
            .foregroundStyle(.primary)
        
        WorkoutSetView()
    }
}

#Preview ("WorkoutExerciseView"){
    let workoutExercisePreview = WorkoutExercise(
        exercise: "Bench Press",
        order: 1,
    )

    WorkoutExerciseView(workoutExercise: workoutExercisePreview)
        .modelContainer(makeWorkoutExercisePreviewContainer())
}
