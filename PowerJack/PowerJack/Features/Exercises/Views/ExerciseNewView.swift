//
//  ExerciseNewView.swift
//  PowerJack
//
//  Created on 7/5/26.
//

import SwiftData
import SwiftUI

struct ExerciseNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSave: (Exercise) -> Void

    @State private var draft: ExerciseDraft
    @State private var saveErrorMessage: String?

    init(name: String = "", primaryMuscle: Muscle? = nil, onSave: @escaping (Exercise) -> Void) {
        self.onSave = onSave
        var draft = ExerciseDraft(name: name)
        draft.primaryMuscle = primaryMuscle
        _draft = State(initialValue: draft)
    }

    var body: some View {
        content.traceScreen("New Exercise")
    }

    @ViewBuilder
    private var content: some View {
        ExerciseForm(
            draft: $draft,
            editExistingExercise: false,
            onSubmit: save
        )
        .saveErrorAlert($saveErrorMessage)
    }

    private func save() {
        guard let exercise = draft.makeExercise() else { return }

        modelContext.insert(exercise)
        draft.applyMovement(to: exercise)
        do {
            try modelContext.save()
            onSave(exercise)
            dismiss()
        } catch {
            // Deleting the exercise deletes the joint action rows it got.
            modelContext.delete(exercise)
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview("ExerciseNew - Default") {
    NavigationPreviewHost(modelContainer: PowerJackSeed.makeInMemoryContainer()) {
        ExerciseNewView(onSave: { _ in })
    }
}

#Preview("ExerciseNew - From Search") {
    NavigationPreviewHost(modelContainer: PowerJackSeed.makeInMemoryContainer()) {
        ExerciseNewView(name: "Landmine Press", onSave: { _ in })
    }
}
