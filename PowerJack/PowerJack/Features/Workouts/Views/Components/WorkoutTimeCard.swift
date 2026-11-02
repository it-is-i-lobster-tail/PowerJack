//
//  WorkoutTimeCard.swift
//  PowerJack
//
//  The workout's time in large digits, on the Review page and the summary.
//

import SwiftUI

struct WorkoutTimeCard: View {
    let title: String
    let duration: TimeInterval
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(duration.elapsedText)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LayoutMetrics.sectionSpacing)
        .powerJackGlassPanel()
        .accessibilityElement(children: .combine)
    }
}

#Preview("WorkoutTimeCard") {
    WorkoutTimeCard(title: "Workout timer", duration: 2538, caption: "Started 5:12 PM")
        .padding()
}
