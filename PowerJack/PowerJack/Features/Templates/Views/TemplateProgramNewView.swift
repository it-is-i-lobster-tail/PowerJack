//
//  TemplateProgramNew.swift
//  PowerJack
//
//  Created by trogdor on 7/26/26.
//

import SwiftUI
import SwiftData

/// Creates a template on the first edit, then saves every change like the edit screen.
struct TemplateProgramNew: View {
    @Environment(\.modelContext) private var modelContext

    @State private var draft = TemplateProgramDraft()
    @State private var templateProgram: TemplateProgram?
    @State private var saveErrorMessage: String?

    var body: some View {
        TemplateForm(
            editExistingExercise: false,
            draft: $draft
        )
        .onChange(of: draft.snapshot) {
            save()
        }
        .saveErrorAlert($saveErrorMessage)
    }

    private func save() {
        do {
            if let templateProgram {
                guard draft.apply(to: templateProgram) else { return }
                try modelContext.save()
            } else {
                templateProgram = try draft.insertNewTemplate(into: modelContext)
            }
        } catch {
            modelContext.rollback()
            if let templateProgram {
                draft = TemplateProgramDraft(templateProgram: templateProgram)
            }
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview("TemplateProgramNew") {
    NavigationPreviewHost(modelContainer: PowerJackSeed.exercises().container) {
        TemplateProgramNew()
    }
}
