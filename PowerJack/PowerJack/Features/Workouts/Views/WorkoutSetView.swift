//
//  WorkoutSetView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI

struct WorkoutSetView: View {
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    private static let paddingHorizontal = 13.0
    private static let paddingVertical = 10.0
    private static let frameWidth = 50.0
    private static let animationDuration = 0.050

    @Bindable var workoutSet: WorkoutSet

    private var repsIsFocused: Bool {
        focusedSetField.wrappedValue == .reps(workoutSet.id)
    }

    private var weightIsFocused: Bool {
        focusedSetField.wrappedValue == .weight(workoutSet.id)
    }

    private var repsBinding: Binding<Int?> {
        Binding(
            get: { workoutSet.reps },
            set: { newValue in
                guard let newValue else {
                    workoutSet.reps = nil
                    return
                }

                workoutSet.reps = min(max(newValue, 1), 100)
            }
        )
    }

    private var plannedRepsPrompt: Text {
        guard let plannedReps = workoutSet.repsPlanned else {
            return Text("2RIR")
        }

        return Text(plannedReps, format: .number)
    }

    private var plannedWeightPrompt: Text {
        guard let plannedWeight = workoutSet.weightInPoundsPlanned else {
            return Text("")
        }

        return Text(plannedWeight, format: .number)
    }

    var body: some View {
        GlassEffectContainer(spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .center, spacing: 6) {
                Text(workoutSet.order + 1, format: .number)
                    .frame(width: 28, alignment: .leading)
                    .font(.title3)
                    .foregroundStyle(.primary)

                Text("Reps")
                    .frame(width: 30, alignment: .trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "Actual Reps",
                    value: repsBinding,
                    format: .number,
                    prompt: plannedRepsPrompt,
                )
                .keyboardType(.numberPad)
                .frame(width: Self.frameWidth)
                .padding(.horizontal, Self.paddingHorizontal)
                .padding(.vertical, Self.paddingVertical)
                .font(.default)
                .focused(focusedSetField, equals: .reps(workoutSet.id))
                .transition(
                    .scale(scale: 0.95, anchor: .center)
                    .combined(with: .opacity)
                )
                .glassEffect(
                    .regular
                        .tint(
                            repsIsFocused
                                ? .blue.opacity(VisualOpacity.light)
                                : .gray.opacity(VisualOpacity.subtle)
                        )
                        .interactive(),
                    in: .rect(cornerRadius: 26)
                )

                Text("Weight")
                    .frame(width: 43, alignment: .trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "Actual weight",
                    value: $workoutSet.weightInPounds,
                    format: .number.precision(.fractionLength(0...1)),
                    prompt: plannedWeightPrompt
                )
                .keyboardType(.numberPad)
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
                        .tint(
                            weightIsFocused
                                ? .blue.opacity(VisualOpacity.light)
                                : .gray.opacity(VisualOpacity.subtle)
                        )
                        .interactive(),
                    in: .rect(cornerRadius: 26)
                )

                ZStack {
                    Button(action: toggleCompletion) {
                        Image(systemName: "circle")
                            .font(.system(size: 35, weight: .thin))
                    }

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
                            .allowsHitTesting(false)
                    } else if workoutSet.locked {
                        Image(systemName: "lock")
                            .font(.system(size: 13, weight: .semibold))
                            .allowsHitTesting(false)
                    }
                }
                .padding(.leading, 15)
                .frame(width: 32, height: 32)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
            .animation(.easeInOut(duration: Self.animationDuration), value: focusedSetField.wrappedValue)
            .powerJackGlassCard()
        }
    }

    private func toggleCompletion() {
        if workoutSet.status != .complete {
            withAnimation {
                completeSet()
            }
        } else {
            workoutSet.start()
        }
    }

    private func completeSet() {
        if workoutSet.reps == nil {
            workoutSet.reps = workoutSet.repsPlanned
        }

        if workoutSet.weightTenthsPounds == nil {
            workoutSet.weightTenthsPounds = workoutSet.weightTenthsPlannedPounds
        }
        workoutSet.complete()
    }
}
