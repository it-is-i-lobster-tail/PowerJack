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
            // Built-in exercises show their name, equipment and muscles but keep them fixed.
            Group {
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
            }
            .disabled(draft.isBuiltIn)

            ExerciseRepRangeField(
                minReps: $draft.minReps,
                maxReps: $draft.maxReps,
                height: boxHeight
            )

            ExerciseFatigueLevelField(
                fatigueLevel: $draft.fatigueLevel,
                customRestTime: $draft.customRestTime,
                fatigueRestTime: draft.fatigueRestTime,
                height: boxHeight
            )

            ExerciseFormNote(isBuiltIn: draft.isBuiltIn)
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

private struct ExerciseFatigueLevelField: View {
    @Binding var fatigueLevel: FatigueLevel
    @Binding var customRestTime: Int?
    let fatigueRestTime: Int
    let height: CGFloat

    private var restDetail: LocalizedStringKey {
        if let customRestTime {
            return "Custom rest · \(Duration.seconds(customRestTime).minuteSecondText) between sets"
        }
        return "\(fatigueLevel.restLength.name) rest · \(fatigueLevel.restLength.duration.minuteSecondText) between sets"
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            FormFieldLabel(
                systemImage: "timer",
                title: "Fatigue Level",
                detail: restDetail
            )
            Picker("Fatigue Level", selection: $fatigueLevel) {
                ForEach(FatigueLevel.allCases) { fatigueLevel in
                    Text(fatigueLevel.name)
                        .tag(fatigueLevel)
                }
            }
            .pickerStyle(.segmented)
            ExerciseCustomRestRow(
                customRestTime: $customRestTime,
                fatigueRestTime: fatigueRestTime
            )
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .padding(.vertical, LayoutMetrics.compactSpacing)
        .frame(maxWidth: .infinity, minHeight: height)
        .powerJackGlassCard(interactive: true)
    }
}

/// Replaces the fatigue level's rest with a time of the user's own. Clearing it goes back to the fatigue level.
private struct ExerciseCustomRestRow: View {
    @Binding var customRestTime: Int?
    let fatigueRestTime: Int

    var body: some View {
        HStack {
            if let customRestTime {
                Button("Clear Custom Rest", systemImage: "xmark.circle.fill") {
                    withAnimation(.snappy) { self.customRestTime = nil }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                Stepper(
                    "Custom \(Duration.seconds(customRestTime).minuteSecondText)",
                    value: Binding(
                        get: { self.customRestTime ?? fatigueRestTime },
                        set: { self.customRestTime = $0 }
                    ),
                    in: ExerciseDraft.restLimits,
                    step: ExerciseDraft.restStep
                )
                .monospacedDigit()
            } else {
                Button("Set Custom Rest", systemImage: "plus.circle") {
                    withAnimation(.snappy) { customRestTime = fatigueRestTime }
                }
                Spacer()
            }
        }
        .font(.caption)
    }
}

private struct ExerciseFormNote: View {
    let isBuiltIn: Bool

    var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text(isBuiltIn
                 ? "Built-in exercises keep their name, equipment and muscles."
                 : "You can edit these details at any time.")
                .font(.caption)
            Spacer()
        }
    }
}
