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
                height: boxHeight
            )

            ExerciseRestField(
                customRestTime: $draft.customRestTime,
                fatigueLevel: draft.fatigueLevel,
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
    let height: CGFloat

    var body: some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            FormFieldLabel(
                systemImage: "bolt.heart",
                title: "Fatigue Level",
                detail: "\(fatigueLevel.restLength.name) rest · \(fatigueLevel.restLength.duration.minuteSecondText)"
            )
            Picker("Fatigue Level", selection: $fatigueLevel) {
                ForEach(FatigueLevel.allCases) { fatigueLevel in
                    Text(fatigueLevel.name)
                        .tag(fatigueLevel)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .padding(.vertical, LayoutMetrics.compactSpacing)
        .frame(maxWidth: .infinity, minHeight: height)
        .powerJackGlassCard(interactive: true)
    }
}

/// Shows the rest this exercise uses. Tapping opens a wheel; turning it sets a custom rest,
/// and the reset button goes back to the fatigue level's rest.
private struct ExerciseRestField: View {
    @Binding var customRestTime: Int?
    let fatigueLevel: FatigueLevel
    let fatigueRestTime: Int
    let height: CGFloat

    @State private var isExpanded = false

    private var restTime: Int { customRestTime ?? fatigueRestTime }

    private var detail: LocalizedStringKey {
        customRestTime == nil ? "From fatigue level" : "Custom for this exercise"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    FormFieldLabel(systemImage: "timer", title: "Rest Between Sets", detail: detail)
                    Text(Duration.seconds(restTime).minuteSecondText)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(customRestTime == nil ? Color.primary : Color.accentColor)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Duration.seconds(restTime).minuteSecondText)
            .accessibilityHint(isExpanded ? "Hides the rest picker" : "Shows the rest picker")

            if isExpanded {
                MinuteSecondWheel(
                    seconds: Binding(
                        get: { restTime },
                        set: { customRestTime = $0 }
                    )
                )
                .frame(height: 150)
            }

            if customRestTime != nil {
                Button {
                    withAnimation(.snappy) { customRestTime = nil }
                } label: {
                    Label(
                        "Reset to \(fatigueLevel.name) · \(Duration.seconds(fatigueRestTime).minuteSecondText)",
                        systemImage: "arrow.counterclockwise"
                    )
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.bottom, LayoutMetrics.sectionSpacing)
            }
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity)
        .powerJackGlassCard(interactive: true)
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
