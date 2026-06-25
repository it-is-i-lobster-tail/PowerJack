//
//  WorkoutSetRowView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftUI
import SwiftData


struct WorkoutSetRowView: View {
    @Bindable var workoutSet: WorkoutSet
    @FocusState private var focusedField: Field?
    
    private static let paddingHorizontal = 13.0
    private static let paddingVertical = 10.0
    private static let frameWidth = 50.0
    private static let focusOpacity = 0.14
    private static let nonFocusOpacity = 0.11
    private static let animationtime = 0.125
    
    enum Field {
        case reps
        case weight
    }

    var body: some View {
        let repsIsFocused = focusedField == .reps
        let weightIsFocused = focusedField == .weight

        HStack(alignment: .center, spacing: 6) {
            Text("\(workoutSet.order)")
            
            Text("Reps")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("2RIR", value: $workoutSet.reps, format: .number)
                .keyboardType(.numberPad)
                .frame(width: Self.frameWidth)
                .padding(.horizontal, Self.paddingHorizontal)
                .padding(.vertical, Self.paddingVertical)
                .font(.subheadline)
                .background(repsIsFocused ? Color.accentColor.opacity(Self.focusOpacity) : Color.gray.opacity(Self.nonFocusOpacity))
                .clipShape(Capsule())
                .focused($focusedField, equals: .reps)

            Text(
                "Weight"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            TextField("lb", value: $workoutSet.weightTenthsPounds, format: .number)
                .keyboardType(.numberPad)
                .frame(width: Self.frameWidth)
                .padding(.horizontal, Self.paddingHorizontal)
                .padding(.vertical, Self.paddingVertical)
                .font(.subheadline)
                .background(weightIsFocused ? Color.accentColor.opacity(Self.focusOpacity) : Color.gray.opacity(Self.nonFocusOpacity))
                .clipShape(Capsule())
                .focused($focusedField, equals: .weight)

        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeInOut(duration: Self.animationtime), value: focusedField)
    }
}

#Preview("WorkoutSetRowView") {
    WorkoutSetRowView(
        workoutSet: WorkoutSet(
            order: 1,
            reps: 15,
            weightTenthsPounds: 1350
        )
    )
    .modelContainer(for: WorkoutSet.self, inMemory: true)
}
