//
//  WorkoutExerciseViewPreview.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftData

func makeWorkoutExercisePreviewContainer() -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: WorkoutSet.self,
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
