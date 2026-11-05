//
//  TopSetRating.swift
//  PowerJack
//
//  The reps-left tap after a PowerJack entry's TOP set (R4.1). It sits under the TOP set while
//  the lifter rests, so nothing covers the rest timer. Left unanswered, the feedback asks it.
//

import SwiftData
import SwiftUI

struct TopSetRating: View {
    @Environment(\.modelContext) private var modelContext

    let workoutExercise: WorkoutExercise

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Text("Top set: how many more reps could you have done?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: LayoutMetrics.compactSpacing) {
                ForEach(RepsInReserve.allCases) { option in
                    Button {
                        withAnimation { workoutExercise.rateTopSets(option) }
                        try? modelContext.save()
                    } label: {
                        Text(option.valueText)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(uiColor: .secondarySystemFill), in: .rect(cornerRadius: LayoutMetrics.cardCornerRadius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                }
            }
        }
    }
}
