//
//  TemplateProgramDetailView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

struct TemplateProgramDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let onSave: (TemplateProgram) -> Void
    let templateProgram: TemplateProgram
    
    @State private var draft: TemplateProgramDraft
    @State private var saveErrorMessage: String?
    
    init(
        templateProgram: TemplateProgram,
        onSave: @escaping (TemplateProgram) -> Void = { _ in}
    ) {
        self.templateProgram = templateProgram
        self.onSave = onSave
        _draft = State(initialValue: TemplateProgramDraft(
            templateProgram: templateProgram
        ))
    }

    var body: some View {
        TemplateForm(
            editExistingExercise: false,
            onSave: save,
            draft: $draft
        )
        .saveErrorAlert($saveErrorMessage)
    }

    private func save() {
        let originalDraft = TemplateProgramDraft(
            templateProgram: templateProgram
        )
        guard draft.apply(to: templateProgram) else { return }

        do {
            try modelContext.save()
            onSave(templateProgram)
            dismiss()
        } catch {
            _ = originalDraft.apply(to: templateProgram)
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview("TemplateProgramDetailView") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        TemplateProgramDetailView(templateProgram: scenario.templateProgram)
    }
}
