//
//  WorkoutSetView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData

struct WorkoutSetView: View {
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    private static let paddingHorizontal = 13.0
    private static let paddingVertical = 10.0
    private static let frameWidth = 50.0
    private static let animationDuration = 0.050
    /// Pause after the last keystroke before a fully logged set completes itself.
    static let autoCompleteDelay: Duration = .milliseconds(1200)

    @Environment(\.modelContext) private var modelContext
    @Bindable var workoutSet: WorkoutSet
    let repsOnly: Bool
    let onWeightChange: (Int?) -> Void
    let onAutoComplete: () -> Void

    // Text-backed so the model updates on every keystroke.
    @State private var repsText: String
    @State private var weightText: String
    // Only edits made in this view arm auto-completion, never initial or restored values.
    @State private var autoCompleteArmed = false

    init(
        focusedSetField: FocusState<FocusedSetField?>.Binding,
        workoutSet: WorkoutSet,
        repsOnly: Bool = false,
        onWeightChange: @escaping (Int?) -> Void = { _ in },
        onAutoComplete: @escaping () -> Void = {}
    ) {
        self.focusedSetField = focusedSetField
        self.workoutSet = workoutSet
        self.repsOnly = repsOnly
        self.onWeightChange = onWeightChange
        self.onAutoComplete = onAutoComplete
        _repsText = State(initialValue: Self.text(forReps: workoutSet.reps))
        _weightText = State(initialValue: Self.text(forWeight: workoutSet.weightInPounds))
    }

    private var repsIsFocused: Bool {
        focusedSetField.wrappedValue == .reps(workoutSet.id)
    }

    private var weightIsFocused: Bool {
        focusedSetField.wrappedValue == .weight(workoutSet.id)
    }

    private var isEditable: Bool {
        workoutSet.status == .active && !workoutSet.locked
    }

    /// Reps above `Exercise.maxRepsAllowed` are shown as invalid and never saved.
    private var repsInvalid: Bool {
        guard let reps = Int(repsText) else { return false }
        return !WorkoutSet.isValidReps(reps)
    }

    private var isFullyLogged: Bool {
        workoutSet.reps != nil && (repsOnly || workoutSet.weightTenthsPounds != nil)
    }

    /// A set can only be checked off once its weight and reps are entered; a checked set can always be unchecked.
    private var canToggleCompletion: Bool {
        guard !workoutSet.locked else { return false }
        if workoutSet.status == .complete { return true }
        return isFullyLogged && !repsInvalid
    }

    private var plannedRepsPrompt: Text {
        guard let plannedReps = workoutSet.repsPlanned else {
            return Text("2RIR")
        }

        return Text(plannedReps, format: .number)
    }

    private var plannedWeightPrompt: Text {
        guard let plannedWeight = workoutSet.weightInPoundsPlanned else {
            return Text(repsOnly ? "BW" : "")
        }

        return Text(plannedWeight, format: .number)
    }

    private struct AutoCompleteKey: Hashable {
        let reps: Int?
        let weight: Int?
    }

    private var autoCompleteKey: AutoCompleteKey {
        AutoCompleteKey(reps: workoutSet.reps, weight: workoutSet.weightTenthsPounds)
    }

    var body: some View {
        GlassEffectContainer(spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .center, spacing: 6) {
                Text(workoutSet.order + 1, format: .number)
                    .frame(width: 28, alignment: .leading)
                    .font(.title3)
                    .foregroundStyle(.primary)

                Text("Weight")
                    .frame(width: 43, alignment: .trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "Actual weight",
                    text: $weightText,
                    prompt: plannedWeightPrompt
                )
                .keyboardType(.decimalPad)
                .disabled(!isEditable)
                .frame(width: Self.frameWidth)
                .padding(.horizontal, Self.paddingHorizontal)
                .padding(.vertical, Self.paddingVertical)
                .font(.default)
                .focused(focusedSetField, equals: .weight(workoutSet.id))
                .transition(
                    .scale(scale: 0.95, anchor: .center)
                    .combined(with: .opacity)
                )
                .glassEffect(
                    .regular
                        .tint(fieldTint(isFocused: weightIsFocused, isInvalid: false))
                        .interactive(),
                    in: .rect(cornerRadius: 26)
                )
                .accessibilityLabel("Set \(workoutSet.order + 1) weight")

                Text("Reps")
                    .frame(width: 30, alignment: .trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "Actual Reps",
                    text: $repsText,
                    prompt: plannedRepsPrompt
                )
                .keyboardType(.numberPad)
                .disabled(!isEditable)
                .frame(width: Self.frameWidth)
                .padding(.horizontal, Self.paddingHorizontal)
                .padding(.vertical, Self.paddingVertical)
                .font(.default)
                .foregroundStyle(repsInvalid ? .red : .primary)
                .focused(focusedSetField, equals: .reps(workoutSet.id))
                .transition(
                    .scale(scale: 0.95, anchor: .center)
                    .combined(with: .opacity)
                )
                .glassEffect(
                    .regular
                        .tint(fieldTint(isFocused: repsIsFocused, isInvalid: repsInvalid))
                        .interactive(),
                    in: .rect(cornerRadius: 26)
                )
                .accessibilityLabel("Set \(workoutSet.order + 1) reps")

                Button(action: toggleCompletion) {
                    ZStack {
                        Image(systemName: "circle")
                            .font(.system(size: 35, weight: .thin))

                        if workoutSet.status == .complete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 17, weight: .bold))
                                .transition(
                                    .symbolEffect(
                                        .drawOn,
                                        options: .speed(2.2)
                                    )
                                )
                                .foregroundStyle(.green)
                        } else if workoutSet.status == .skipped {
                            Image(systemName: "forward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else if workoutSet.locked {
                            Image(systemName: "lock")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    // Only the circle is tappable, so taps near the reps field stay there.
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                }
                // A plain style stops the List from turning the whole row into this button.
                .buttonStyle(.plain)
                .disabled(!canToggleCompletion)
                .opacity(canToggleCompletion || workoutSet.locked ? 1 : VisualOpacity.light)
                .accessibilityLabel("Set \(workoutSet.order + 1) complete")
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
            .animation(.easeInOut(duration: Self.animationDuration), value: focusedSetField.wrappedValue)
            .powerJackGlassCard()
        }
        .onChange(of: repsText) { _, newValue in
            updateReps(from: newValue)
        }
        .onChange(of: weightText) { _, newValue in
            updateWeight(from: newValue)
        }
        .onChange(of: workoutSet.reps) { _, newValue in
            // Keep text in sync when the model changes elsewhere, e.g. completing with planned values.
            if Int(repsText) != newValue, !repsInvalid {
                repsText = Self.text(forReps: newValue)
            }
        }
        .onChange(of: workoutSet.weightTenthsPounds) { _, _ in
            if parsedWeight(weightText) != workoutSet.weightInPounds {
                weightText = Self.text(forWeight: workoutSet.weightInPounds)
            }
        }
        .task(id: autoCompleteKey) {
            await autoCompleteAfterDebounce()
        }
    }

    private func fieldTint(isFocused: Bool, isInvalid: Bool) -> Color {
        if isInvalid { return .red.opacity(VisualOpacity.light) }
        return isFocused
            ? .blue.opacity(VisualOpacity.light)
            : .gray.opacity(VisualOpacity.subtle)
    }

    private func updateReps(from text: String) {
        guard isEditable else { return }
        let digits = text.filter(\.isNumber)
        if digits != text {
            repsText = digits
            return
        }
        // Invalid (e.g. > 30) reps are stored as nil so they can never be saved.
        let newValue = Int(digits)
        guard newValue != workoutSet.reps else { return }
        autoCompleteArmed = true
        workoutSet.reps = newValue
    }

    private func updateWeight(from text: String) {
        guard isEditable else { return }
        let newValue = parsedWeight(text)
        guard newValue != workoutSet.weightInPounds else { return }
        autoCompleteArmed = true
        workoutSet.weightInPounds = newValue
        onWeightChange(workoutSet.weightTenthsPounds)
    }

    private func parsedWeight(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    /// `task(id:)` restarts on every edit, so this only fires once typing pauses.
    private func autoCompleteAfterDebounce() async {
        guard autoCompleteArmed, isEditable, isFullyLogged, !repsInvalid else { return }

        do {
            try await Task.sleep(for: Self.autoCompleteDelay)
        } catch {
            return
        }

        guard autoCompleteArmed, isEditable, isFullyLogged, !repsInvalid else { return }
        autoCompleteArmed = false
        withAnimation {
            completeSet()
        }
        onAutoComplete()
    }

    private func toggleCompletion() {
        if workoutSet.status != .complete {
            withAnimation {
                completeSet()
            }
        } else {
            autoCompleteArmed = false
            workoutSet.start()
        }
    }

    private func completeSet() {
        workoutSet.complete()
        try? modelContext.save()
    }

    private static func text(forReps reps: Int?) -> String {
        reps.map(String.init) ?? ""
    }

    private static func text(forWeight weight: Double?) -> String {
        guard let weight else { return "" }
        return weight.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }
}
