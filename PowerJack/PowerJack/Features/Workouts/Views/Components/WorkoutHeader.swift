//
//  WorkoutHeader.swift
//  PowerJack
//
//  The glass bubble at the top of a workout: the exercise on screen with its equipment under it.
//  While the bars fade away it steps down to the name alone, in a smaller font.
//

import SwiftUI

struct WorkoutHeader: View {
    /// The exercise on screen. Nil on the Review page.
    let exercise: Exercise?
    /// True while the bars are faded: the name alone, smaller, and no wider than it was,
    /// so it doesn't grow into the room the bar's buttons leave.
    var isCompact = false

    @State private var width: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            Text(exercise?.exerciseName ?? "Review")
                .font(isCompact ? .headline : .title3.weight(.semibold))
            if let exercise, !isCompact {
                Text(exercise.equipment.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
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
        .frame(maxWidth: isCompact ? width : nil)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
            if !isCompact { width = newWidth }
        }
        // Shrinks and grows in step with the bars' fade.
        .animation(IdleControls.fade, value: isCompact)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
