//
//  ExerciseForm.swift
//  PowerJack
//
//  Created on 7/8/26.
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

                NavigationLink {
                    EquipmentList { base, name in
                        draft.equipment = base
                        draft.customEquipmentName = name
                    }
                } label: {
                    HStack {
                        FormFieldLabel(
                            systemImage: "figure.cross.training",
                            title: "Equipment",
                            detail: LocalizedStringKey(draft.customEquipmentName ?? draft.equipment?.displayName ?? "Select equipment")
                        )
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, LayoutMetrics.sectionSpacing)
                .frame(height: boxHeight)
                .powerJackGlassCard(interactive: true)

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

            // Built-in exercises get their movement from the catalog.
            if !draft.isBuiltIn {
                NavigationLink {
                    MovesLikeList(selected: draft.movesLike) { draft.choose(movesLike: $0) }
                } label: {
                    HStack {
                        FormFieldLabel(
                            systemImage: "figure.strengthtraining.traditional",
                            title: "Moves Like",
                            detail: LocalizedStringKey(draft.movesLikeName ?? "Not set")
                        )
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, LayoutMetrics.sectionSpacing)
                .frame(height: boxHeight)
                .powerJackGlassCard(interactive: true)
                .accessibilityHint("Picks the built-in exercise this one moves like")
            }

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
        .task(id: ProposalInput(draft)) { await proposeMovesLike() }
    }

    private func handlePrimaryMuscleChange() {
        draft.removePrimaryFromSecondary()
    }

    /// What a "Moves like" proposal reads.
    private struct ProposalInput: Hashable {
        let name: String
        let equipment: Equipment?
        let primary: Muscle?

        init(_ draft: ExerciseDraft) {
            name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            equipment = draft.equipment
            primary = draft.primaryMuscle
        }
    }

    /// Proposes a built-in once typing pauses, until the lifter picks one.
    private func proposeMovesLike() async {
        guard draft.wantsMovesLikeProposal else { return }
        let input = ProposalInput(draft)
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let key = input.name.count < 3 ? nil
            : await MovesLike.propose(name: input.name, equipment: input.equipment, primary: input.primary)
        guard !Task.isCancelled else { return }
        draft.propose(movesLike: key)
    }
}

/// The built-in exercises, searchable, plus None. Choosing one sets what an own exercise moves like.
private struct MovesLikeList: View {
    let selected: String?
    let onChoose: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var shown: [ExerciseCatalog.Entry] {
        let query = ExerciseQuery(searchText)
        guard !query.isEmpty else {
            // The lift picked now comes first, then the rest by name.
            return ExerciseCatalog.entries.sorted { left, right in
                let (leftPicked, rightPicked) = ("catalog:\(left.id)" == selected, "catalog:\(right.id)" == selected)
                if leftPicked != rightPicked { return leftPicked }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        }
        return MovesLike.index.rank(query).compactMap { MovesLike.entry($0.key) }
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                row("None", detail: nil, key: nil)
            }
            ForEach(shown, id: \.id) { entry in
                row(entry.name, detail: entry.equipmentName ?? entry.equipment.displayName, key: "catalog:\(entry.id)")
            }
        }
        .overlay {
            if !searchText.isEmpty && shown.isEmpty {
                EmptyStateView(title: "No matching exercises", systemImage: "magnifyingglass")
            }
        }
        .navigationTitle("Moves Like")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search built-in exercises")
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func row(_ title: String, detail: String?, key: String?) -> some View {
        Button {
            onChoose(key)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if key == selected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        ScrollViewReader { proxy in
            card(scrollProxy: proxy)
        }
    }

    private static let cardID = "restBetweenSets"

    private func card(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                } completion: {
                    // The card sits near the bottom of the form, so bring the opened wheel into view.
                    guard isExpanded else { return }
                    withAnimation(.snappy) { scrollProxy.scrollTo(Self.cardID, anchor: .bottom) }
                }
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
                .tint(.blue)
                .controlSize(.large)
                .padding(.bottom, LayoutMetrics.sectionSpacing)
            }
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity)
        .powerJackGlassCard(interactive: true)
        .id(Self.cardID)
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
