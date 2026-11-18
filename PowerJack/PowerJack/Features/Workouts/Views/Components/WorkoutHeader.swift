//
//  WorkoutHeader.swift
//  PowerJack
//
//  The glass bubble at the top of a workout: the exercise on screen with its equipment under it.
//

import SwiftUI

struct WorkoutHeader: View {
    /// The exercise on screen. Nil on the Review page.
    let exercise: Exercise?

    var body: some View {
        VStack(spacing: 0) {
            Text(exercise?.exerciseName ?? "Review")
                .font(.title3.weight(.semibold))
            if let exercise {
                Text(exercise.equipment.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        // A long name tightens and shrinks before it's cut short, so it stays one line in the bar.
        .lineLimit(1)
        .allowsTightening(true)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            // The same glass as the bottom bar, so the top and bottom match.
            Color.clear
                .glassEffect(.powerJackBar, in: .capsule)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
