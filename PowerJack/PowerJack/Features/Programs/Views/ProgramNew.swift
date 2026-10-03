// xcode: set sdk=iOS

//
//  ProgramNew.swift
//  PowerJack
//
//  Created by trogdor on 7/18/26.
//

import SwiftData
import SwiftUI

struct ProgramNew: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProgramsRouter.self) private var router
    @Query private var programs: [Program]

    private let boxHeight: CGFloat = 55
    private let programLengths = Array(stride(from: 2, through: 12, by: 2))

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
                Text("\(number) weeks")
            }

            ProgramTemplateSelection(
                boxHeight: boxHeight,
                createTemplate: presentTemplateCreator,
                selectedTemplate: $draft.templateProgram
            )
        } footer: {
            FormSubmitButton(
                title: "Save",
                isEnabled: draft.canSave,
                action: save
            )
        }
        .sheet(isPresented: $isCreatingTemplate) {
            TemplateProgramListView(
                onSelect: handleNewTemplate
            )
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

    /// Saves the program, makes it the active one and opens its first workout.
    private func save() {
        guard let program = draft.makeProgram() else { return }
        let previousProgram = programs.active

        do {
            try modelContext.insertAndSave(program)
        } catch {
            saveErrorMessage = error.localizedDescription
            return
        }

        if let previousProgram {
            previousProgram.stop()
            previousProgram.stopAndCascade()
        }
        program.start()
        program.nextWorkout?.startAndCascade()

        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = error.localizedDescription
            return
        }
        // Replaces this form with the program and its first workout.
        router.restore(activeProgram: program)
    }
}

private struct ProgramTemplateSelection: View {
    let boxHeight: CGFloat
    let createTemplate: () -> Void

    @Binding var selectedTemplate: TemplateProgram?

    var body: some View {
        Button {
            createTemplate()
        } label: {
            HStack(spacing: 12) {
                FormFieldLabel(
                    systemImage: "target",
                    title: "Template",
                    detail: "Select program's template"
                )

                if let template = selectedTemplate {
                    Text(template.templateName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
        .powerJackGlassCard(interactive: true)
    }
}

#Preview("ProgramNew - Loaded") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ProgramNew()
    }
}

#Preview("ProgramNew - No Templates") {
    NavigationPreviewHost(modelContainer: PowerJackSeed.makeInMemoryContainer()) {
        ProgramNew()
    }
}
