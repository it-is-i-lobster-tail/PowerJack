//
//  WorkoutSetRowView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData


struct WorkoutSetView: View {
    let screenWidth: CGFloat
    @Bindable var workoutSet: WorkoutSet
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    
    private static let paddingHorizontal = 13.0
    private static let paddingVertical = 10.0
    private static let frameWidth = 50.0
    private static let focusOpacity = 0.14
    private static let nonFocusOpacity = 0.11
    private static let animationtime = 0.050

    var body: some View {
        let repsIsFocused = focusedSetField.wrappedValue == .reps(workoutSet.id)
        let weightIsFocused = focusedSetField.wrappedValue == .weight(workoutSet.id)

        HStack(alignment: .center, spacing: 6) {
            Text("\(workoutSet.order + 1)")
                .frame(width: 28, alignment: .leading)
                .font(.title3)
                .foregroundStyle(.primary)

            Text("Reps")
                .frame(width: 30, alignment: .trailing)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("2RIR", value: $workoutSet.reps, format: .number)
                .keyboardType(.decimalPad)
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
                            repsIsFocused ?
                                .blue.opacity(OpacityPJ.focusLight) : .gray.opacity(OpacityPJ.focusThin)),
                    in: .rect(cornerRadius: 26))

            Text(
                "Weight"
            )
            .frame(width: 43, alignment: .trailing)
            .font(.caption)
            .foregroundStyle(.secondary)
            TextField("lb", value: $workoutSet.weightInPounds, format: .number)
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
                            weightIsFocused ?
                                .blue.opacity(OpacityPJ.focusLight) : .gray.opacity(OpacityPJ.focusThin)),
                    in: .rect(cornerRadius: 26))

            ZStack {
                if workoutSet.status == Status.complete {
                    Image(systemName: "checkmark")
                        .font(.title3)
                        .foregroundStyle(.mint)
                }
            }
            .frame(width: 25)
        }
        .frame(alignment: .center)
        .animation(.easeInOut(duration: Self.animationtime), value: focusedSetField.wrappedValue)
    }
}
