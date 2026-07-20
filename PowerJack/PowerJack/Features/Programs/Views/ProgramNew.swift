//
//  ProgramNew.swift
//  PowerJack
//
//  Created by trogdor on 7/18/26.
//

import SwiftData
import SwiftUI

struct ProgramNew: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSave: (Program) -> Void

    private let boxHeight: CGFloat = 55
    private let programLengths = Array(stride(from: 2, through: 12, by: 2))

    @Query(sort: \TemplateProgram.templateName) private var templatePrograms: [TemplateProgram]
    @State private var draft = ProgramDraft()
    @State private var isCreatingTemplate = false
    @State private var saveErrorMessage: String?

    var body: some View {
        GlassFormScaffold(
            navigationTitle: "New Program",
            headerSystemImage: "square.3.layers.3d.top.filled",
            headerTitle: "Start a new program"
        ) {
            GlassPickerField(
                selection: $draft.programLengthWeeks,
                options: programLengths,
                height: boxHeight
            ) {
                FormFieldLabel(
                    systemImage: "calendar",
                    title: "Program Length",
                    detail: "Choose the number of weeks"
                )
            } optionLabel: { number in
                Text(number, format: .number)
            }

            ProgramTemplateSelection(
                boxHeight: boxHeight,
                templatePrograms: templatePrograms,
                selectedTemplate: $draft.templateProgram,
                createTemplate: presentTemplateCreator
            )
        } footer: {
            FormSubmitButton(
                title: "Save",
                isEnabled: draft.canSave,
                action: save
            )
        }
        .navigationDestination(isPresented: $isCreatingTemplate) {
            TemplateProgramNew(onSave: handleNewTemplate)
        }
        .saveErrorAlert($saveErrorMessage)
    }

    private func presentTemplateCreator() {
        isCreatingTemplate = true
    }

    private func handleNewTemplate(_ templateProgram: TemplateProgram) {
        draft.templateProgram = templateProgram
        isCreatingTemplate = false
    }

    private func save() {
        guard let program = draft.makeProgram() else { return }

        do {
            try modelContext.insertAndSave(program)
            onSave(program)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct ProgramTemplateSelection: View {
    let boxHeight: CGFloat
    let templatePrograms: [TemplateProgram]
    let createTemplate: () -> Void

    @Binding var selectedTemplate: TemplateProgram?

    init(
        boxHeight: CGFloat,
        templatePrograms: [TemplateProgram],
        selectedTemplate: Binding<TemplateProgram?>,
        createTemplate: @escaping () -> Void
    ) {
        self.boxHeight = boxHeight
        self.templatePrograms = templatePrograms
        self.createTemplate = createTemplate
        _selectedTemplate = selectedTemplate
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            if templatePrograms.isEmpty {
                Button(action: createTemplate) {
                    FormFieldLabel(
                        systemImage: "doc.badge.plus",
                        title: "Create a Template",
                        detail: "A program needs at least one template"
                    )
                    .padding(.horizontal, LayoutMetrics.sectionSpacing)
                    .frame(maxWidth: .infinity, minHeight: boxHeight)
                }
                .buttonStyle(.plain)
                .powerJackGlassCard(interactive: true)
            } else {
                GlassPickerField(
                    selection: $selectedTemplate,
                    options: templatePrograms,
                    height: boxHeight
                ) {
                    FormFieldLabel(
                        systemImage: "doc.on.doc",
                        title: "Template",
                        detail: "Select a workout template"
                    )
                } optionLabel: { templateProgram in
                    Text(templateProgram.templateName)
                }

                Button("New Template", systemImage: "plus", action: createTemplate)
                    .buttonStyle(.glass)
            }
        }
    }
}

#Preview("ProgramNew - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationStack {
        ProgramNew(onSave: { _ in })
    }
    .modelContainer(scenario.container)
}

#Preview("ProgramNew - No Templates") {
    NavigationStack {
        ProgramNew(onSave: { _ in })
    }
    .modelContainer(PowerJackSeed.makeInMemoryContainer())
}
