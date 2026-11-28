//
//  BuildForMeReview.swift
//  PowerJack
//
//  The built template in the usual template builder, unsaved. Every edit works as it does anywhere
//  else, and nothing is stored until Save Template. Going back asks first only after an edit.
//

import SwiftData
import SwiftUI

struct BuildForMeReview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // The Templates list moves to the saved template's type.
    @AppStorage(TemplateType.selectionKey) private var listedType: TemplateType = .hypertrophy

    /// Called once the template is saved.
    let onSave: () -> Void

    @State private var draft: TemplateProgramDraft
    @State private var isConfirmingDiscard = false
    @State private var saveErrorMessage: String?
    private let built: Layout

    init(draft: TemplateProgramDraft, onSave: @escaping () -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: draft)
        built = Layout(draft)
    }

    var body: some View {
        content.traceScreen("Build for Me Review")
    }

    private var content: some View {
        VStack(spacing: LayoutMetrics.sectionSpacing) {
            TemplateBuilder(draft: $draft)
            FormSubmitButton(title: "Save Template", isEnabled: true, action: save)
                .padding(.horizontal, LayoutMetrics.sectionSpacing)
        }
        .padding(.bottom, LayoutMetrics.sectionSpacing)
        // A plain title: a renamable one crowds the builder's buttons into a More menu. Rename after saving.
        .navigationTitle(draft.templateName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEdited)
        .toolbar {
            if isEdited {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isConfirmingDiscard = true
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .alert("Discard This Template?", isPresented: $isConfirmingDiscard) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your changes haven't been saved.")
        }
        .saveErrorAlert($saveErrorMessage)
    }

    private var isEdited: Bool { Layout(draft) != built }

    private func save() {
        do {
            guard let template = try draft.insertNewTemplate(into: modelContext) else { return }
            listedType = template.templateType
            onSave()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    /// What an edit can change: each day's exercises, order and supersets.
    private struct Layout: Equatable {
        let days: [[String]]

        init(_ draft: TemplateProgramDraft) {
            days = draft.templateWorkoutDrafts.map { day in
                day.templateExerciseDrafts.map { "\($0.id) \($0.supersetID?.uuidString ?? "")" }
            }
        }
    }
}
