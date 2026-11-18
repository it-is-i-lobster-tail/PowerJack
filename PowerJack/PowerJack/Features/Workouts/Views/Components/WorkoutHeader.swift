//
//  WorkoutHeader.swift
//  PowerJack
//
//  The glass bubble at the top of a workout: the exercise on screen with its equipment under it.
//

import SwiftUI

struct WorkoutHeader: View {
    /// Light glass reads heavier than dark over a light page, so it's eased off a little.
    private static let lightGlassOpacity = 0.5

    @Environment(\.colorScheme) private var colorScheme

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
            Color.clear
                .glassEffect(.regular, in: .capsule)
                .opacity(colorScheme == .light ? Self.lightGlassOpacity : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
