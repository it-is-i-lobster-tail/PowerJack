//
//  ExerciseForm.swift
//  PowerJack
//
//  Created by Brendon on 7/8/26.
//

import SwiftUI

struct ExerciseForm: View {
    let editExistingExercise: Bool
    let onSubmit: () -> Void

    private let boxHeight: CGFloat = 85

    @Binding var draft: ExerciseDraft
    @FocusState private var nameIsFocused: Bool

    init(
        draft: Binding<ExerciseDraft>,
        editExistingExercise: Bool,
        onSubmit: @escaping () -> Void
    ) {
        _draft = draft
        self.editExistingExercise = editExistingExercise
        self.onSubmit = onSubmit
    }

    var body: some View {
        GlassFormScaffold(
            navigationTitle: editExistingExercise ? "Edit Exercise" : "New Exercise",
            headerSystemImage: "dumbbell",
            headerTitle: editExistingExercise ? "Edit exercise" : "Create a new exercise"
        ) {
            ValidatedNameField(
                title: "Name",
                prompt: "Exercise name",
                maximumLength: maxExerciseNameLengthInput,
                height: boxHeight,
                text: $draft.name,
                isFocused: $nameIsFocused
            )

            GlassPickerField(
                selection: $draft.equipment,
                options: Equipment.allCases.sorted { $0.rawValue < $1.rawValue },
                height: boxHeight
            ) {
                FormFieldLabel(
                    systemImage: "figure.cross.training",
                    title: "Equipment",
                    detail: "Select equipment"
                )
            } optionLabel: { equipment in
                Text(equipment.rawValue.capitalized)
            }

            GlassPickerField(
                selection: $draft.primaryMuscle,
                options: Muscle.allCases.sorted { $0.rawValue < $1.rawValue },
                height: boxHeight
            ) {
                FormFieldLabel(
                    systemImage: "target",
                    title: "Primary Muscle",
                    detail: "Select primary muscle"
                )
            } optionLabel: { muscle in
                Text(muscle.rawValue.capitalized)
            }

            SecondaryMuscleSelectionLink(
                boxHeight: boxHeight,
                selectedPrimaryMuscle: draft.primaryMuscle,
                selectedSecondaryMuscles: $draft.secondaryMuscles
            )

            ExerciseFormNote()
        } footer: {
            FormSubmitButton(
                title: "Save",
                isEnabled: draft.canSave,
                action: onSubmit
            )
        }
        .onChange(of: draft.primaryMuscle, handlePrimaryMuscleChange)
    }

    private func handlePrimaryMuscleChange() {
        draft.removePrimaryFromSecondary()
    }
}

private struct ExerciseFormNote: View {
    var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("You can edit these details at any time.")
                .font(.caption)
            Spacer()
        }
    }
}
