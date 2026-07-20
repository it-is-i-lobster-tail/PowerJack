//
//  ExerciseNewView.swift
//  PowerJack
//
//  Created by Brendon on 7/5/26.
//

import SwiftData
import SwiftUI

struct ExerciseNewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSave: (Exercise) -> Void

    @State private var draft = ExerciseDraft()
    @State private var saveErrorMessage: String?

    var body: some View {
        ExerciseForm(
            draft: $draft,
            editExistingExercise: false,
            onSubmit: save
        )
        .saveErrorAlert($saveErrorMessage)
    }

    private func save() {
        guard let exercise = draft.makeExercise() else { return }

        do {
            try modelContext.insertAndSave(exercise)
            onSave(exercise)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview("ExerciseNew - Default") {
    NavigationStack {
        ExerciseNewView(onSave: { _ in })
    }
    .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
