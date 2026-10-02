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

    @Binding private var draft: ExerciseDraft
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

            ExerciseRepRangeField(
                minReps: $draft.minReps,
                maxReps: $draft.maxReps,
                height: boxHeight
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

private struct ExerciseRepRangeField: View {
    @Binding var minReps: Int
    @Binding var maxReps: Int
    let height: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            FormFieldLabel(
                systemImage: "repeat",
                title: "Rep Range",
                detail: "\(minReps)–\(maxReps) reps"
            )
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Stepper(
                    "Min \(minReps)",
                    value: $minReps,
                    in: ExerciseDraft.repLimits.lowerBound...maxReps
                )
                .font(.caption)
                Stepper(
                    "Max \(maxReps)",
                    value: $maxReps,
                    in: minReps...ExerciseDraft.repLimits.upperBound
                )
                .font(.caption)
            }
            .fixedSize()
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .powerJackGlassCard(interactive: true)
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
