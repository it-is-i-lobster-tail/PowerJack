//
//  TemplateProgramDetailView.swift
//  PowerJack
//
//  Created by Brendon on 7/3/26.
//

import SwiftData
import SwiftUI

/// Edits a template and saves every valid change as it happens.
struct TemplateProgramDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let templateProgram: TemplateProgram

    @State private var draft: TemplateProgramDraft
    @State private var saveErrorMessage: String?

    init(templateProgram: TemplateProgram) {
        self.templateProgram = templateProgram
        _draft = State(initialValue: TemplateProgramDraft(
            templateProgram: templateProgram
        ))
    }

    var body: some View {
        TemplateForm(
            editExistingExercise: true,
            onSave: nil,
            draft: $draft
        )
        .onChange(of: draft.snapshot) {
            save()
        }
        .saveErrorAlert($saveErrorMessage)
    }

    /// Unfinished changes save too; the template stays a draft until it's complete.
    private func save() {
        guard draft.apply(to: templateProgram) else { return }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            draft = TemplateProgramDraft(templateProgram: templateProgram)
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
