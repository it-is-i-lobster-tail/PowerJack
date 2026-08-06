//
//  ExerciseDetailView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSave: (Exercise) -> Void
    let exercise: Exercise

    @State private var draft: ExerciseDraft
    @State private var saveErrorMessage: String?

    init(
        exercise: Exercise,
        onSave: @escaping (Exercise) -> Void = { _ in },
    ) {
        self.exercise = exercise
        self.onSave = onSave
        _draft = State(initialValue: ExerciseDraft(exercise: exercise))
    }

    var body: some View {
        ExerciseForm(
            draft: $draft,
            editExistingExercise: true,
            onSubmit: save
        )
        .saveErrorAlert($saveErrorMessage)
    }

    private func save() {
        let originalDraft = ExerciseDraft(exercise: exercise)
        guard draft.apply(to: exercise) else { return }

        do {
            try modelContext.save()
            onSave(exercise)
            dismiss()
        } catch {
            _ = originalDraft.apply(to: exercise)
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview("ExerciseDetailView - Barbell") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ExerciseDetailView(
            exercise: scenario.exercises[0],
            onSave: { _ in },
        )
    }
}

#Preview("ExerciseDetailView - Bodyweight") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ExerciseDetailView(
            exercise: scenario.exercises[2],
            onSave: { _ in },
        )
    }
}

#Preview("ExerciseDetailView - Leg Press") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ExerciseDetailView(
            exercise: scenario.exercises[5],
            onSave: { _ in },
        )
    }
}
