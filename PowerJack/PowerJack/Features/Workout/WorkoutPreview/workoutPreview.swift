//
//  workoutPreview.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftData

func makeWorkoutPreviewContainer() -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Workout.self,
        configurations: config
    )
    
    container.mainContext.insert(
        WorkoutSet(
            order: 1,
            reps: 15,
            weightTenthsPounds: 1350
        )
    )
    container.mainContext.insert(
        WorkoutSet(
            order: 2,
            reps: 12,
            weightTenthsPounds: 1350
        )
    )
    return container
}
