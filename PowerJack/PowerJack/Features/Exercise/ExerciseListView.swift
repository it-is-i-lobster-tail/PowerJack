//
//  ExerciseListView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

struct ExerciseListView: View {
    @Query(sort: \Exercise.exerciseName) private var exercises: [Exercise]

    var body: some View {
        List {
            if exercises.isEmpty {
                Text("No exercises")
            } else {
                ForEach(exercises, id: \.self) { exercise in
                    Text(exercise.exerciseName)
                }
            }
        }
    }
}

#Preview("ExerciseListView - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        ExerciseListView()
    }
    .modelContainer(scenario.container)
}

#Preview("ExerciseListView - Empty") {
    NavigationStack {
        ExerciseListView()
    }
    .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
