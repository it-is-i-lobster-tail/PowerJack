//
//  ExerciseSummaryView.swift
//  PowerJack
//
//  Shown after a workout is finished: completed sets per muscle as bars
//  that grow in one row at a time.
//

import SwiftUI

struct ExerciseSummaryView: View {
    /// Sorted most sets first, as `Workout.completedSetsByMuscle` returns them.
    let setCounts: [MuscleSetCount]
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Workout complete!")
                    .font(.largeTitle.bold())

                Text("Today you did")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)

                MuscleBarChart(
                    bars: setCounts.map { MuscleBar(muscle: $0.muscle, value: Double($0.sets)) },
                    reveal: .rowByRow,
                    unit: { $0 == 1 ? "set" : "sets" }
                )
                .padding(.top, LayoutMetrics.compactSpacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutMetrics.sectionSpacing)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onContinue) {
                Text("Done")
                    .font(.title3)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.glassProminent)
            .padding(LayoutMetrics.sectionSpacing)
        }
    }
}

#Preview("ExerciseSummaryView") {
    ExerciseSummaryView(
        setCounts: [
            MuscleSetCount(muscle: .chest, sets: 6),
            MuscleSetCount(muscle: .back, sets: 3),
            MuscleSetCount(muscle: .triceps, sets: 2),
            MuscleSetCount(muscle: .biceps, sets: 1),
        ],
        onContinue: {}
    )
}
