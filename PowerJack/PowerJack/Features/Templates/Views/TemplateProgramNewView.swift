//
//  TemplateProgramNew.swift
//  PowerJack
//
//  Created by trogdor on 7/26/26.
//

import SwiftUI
import SwiftData

struct TemplateProgramNew: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let onSave: (TemplateProgram) -> Void
    
    @State private var draft = TemplateProgramDraft()
    @State private var saveErrorMessage: String?
    
    var body: some View {
        TemplateForm(
            editExistingExercise: false,
            onSave: save,
            draft: $draft
        )
        .saveErrorAlert($saveErrorMessage)
    }

    private func save() {
        guard let templateProgram = draft.makeTemplate() else { return }

        do {
            try modelContext.insertAndSave(templateProgram)
            onSave(templateProgram)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
    
}

#Preview("TemplateProgramNew") {
    NavigationPreviewHost(modelContainer: PowerJackSeed.exercises().container) {
        TemplateProgramNew(onSave: { _ in })
    }
}
