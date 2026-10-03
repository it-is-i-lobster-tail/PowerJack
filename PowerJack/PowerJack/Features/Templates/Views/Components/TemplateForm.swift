//
//  TemplateProgramNew.swift
//  PowerJack
//
//  Created by trogdor on 7/19/26.
//

import SwiftData
import SwiftUI

struct TemplateForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let editExistingExercise: Bool
    /// Nil hides the Save button, for screens that save as the user edits.
    let onSave: (() -> Void)?
    @Binding var draft: TemplateProgramDraft
    
    private let boxHeight: CGFloat = 85
    private let workoutsPerWeekOptions = Array(
        TemplateProgramDraft.minimumWorkoutsPerWeek...TemplateProgramDraft.maximumWorkoutsPerWeek
    )
    
    @FocusState private var nameIsFocused: Bool
    
    var body: some View {
        GlassFormScaffold(
            navigationTitle: editExistingExercise ? "Edit Template" : "New Template",
            headerSystemImage: "square.3.layers.3d.top.filled",
            headerTitle: "Build a reusable workout template"
        ) {
            ValidatedNameField(
                title: "Name",
                prompt: "Template name",
                maximumLength: TemplateProgramDraft.maximumNameLength,
                height: boxHeight,
                text: $draft.templateName,
                isFocused: $nameIsFocused
            )
            
            TemplateFocusSelectionLink(
                boxHeight: boxHeight,
                selectedMuscles: $draft.templateMuscleFocusValue
            )
            
            GlassPickerField(
                selection: $draft.workoutsPerWeek,
                options: workoutsPerWeekOptions,
                height: boxHeight
            ) {
                FormFieldLabel(
                    systemImage: "calendar.badge.clock",
                    title: "Workouts per Week",
                    detail: "Choose two to six workout days"
                )
            } optionLabel: { count in
                Text(count, format: .number)
            }
            
            BuildTemplate(
                boxHeight: boxHeight,
                draft: $draft
            )
            
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("You can edit these details at any time.")
                    .font(.caption)
                Spacer()
            }
            
        } footer: {
            if let onSave {
                FormSubmitButton(
                    title: "Save",
                    isEnabled: draft.canSave,
                    action: onSave
                )
            }
        }
    }
}

private struct TemplateFocusSelectionLink: View {
    let boxHeight: CGFloat

    @Binding var selectedMuscles: [Muscle]

    var body: some View {
        NavigationLink {
            LimitedMuscleSelectionView(
                navigationTitle: "Focus Muscles",
                guidance: "Choose up to \(TemplateProgramDraft.maximumFocusMuscles)",
                maximumSelection: TemplateProgramDraft.maximumFocusMuscles,
                selectedMuscles: $selectedMuscles
            )
        } label: {
            HStack(spacing: 12) {
                FormFieldLabel(
                    systemImage: "target",
                    title: "Focus Muscles",
                    detail: "Choose one to four muscles"
                )

                VStack {
                    ForEach(selectedMuscles) { muscle in
                        Text(muscle.rawValue.localizedCapitalized)
                            .font(.caption2)
                    }
                }
            }
            .padding(.horizontal, LayoutMetrics.sectionSpacing)
        }
        .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
        .powerJackGlassCard(interactive: true)
    }
}

private struct BuildTemplate: View {
    let boxHeight: CGFloat
    @Binding var draft: TemplateProgramDraft
    
    var body: some View {
        NavigationLink {
            TemplateBuilder(
                draft: $draft
            )
        } label: {
            FormFieldLabel(
                systemImage: "target",
                title: "Build Workouts",
                detail: "Set exercises for each workout"
            )
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight)
        .powerJackGlassCard(interactive: true)
    }
}
