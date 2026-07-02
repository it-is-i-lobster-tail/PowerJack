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
    return container
}
