//
//  ExerciseDetailView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    let onSave: (Exercise) -> Void
    let exercise: Exercise
    @State private var draft: ExerciseDraft
    
    
    init(
        exercise: Exercise,
        onSave: @escaping (Exercise) -> Void = { _ in }
    ) {
        self.exercise = exercise
        self.onSave = onSave
        _draft = State(initialValue: ExerciseDraft(exercise: exercise))
    }
    
    var body: some View {
        ExerciseForm(
            draft: $draft,
            onSave: onSave
        )
        .navigationTitle("Edit Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("ExerciseDetailView - Barbell") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        ExerciseDetailView(
            exercise: scenario.exercises[0],
            onSave: { _ in }
        )
    }
    .modelContainer(scenario.container)
}

#Preview("ExerciseDetailView - Bodyweight") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        ExerciseDetailView(
            exercise: scenario.exercises[2],
            onSave: { _ in }
        )
    }
    .modelContainer(scenario.container)
}

#Preview("ExerciseDetailView - Leg Press") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        ExerciseDetailView(
            exercise: scenario.exercises[5],
            onSave: { _ in }
        )
    }
    .modelContainer(scenario.container)
}
