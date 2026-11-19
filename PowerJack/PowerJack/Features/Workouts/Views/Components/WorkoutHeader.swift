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
    /// True while the bars are faded: the name alone, smaller, in a smaller bubble.
    var isCompact = false

    /// The full bubble's size. While compact, the header keeps taking up this much room and the
    /// bubble shrinks in the middle of it, so the navigation bar doesn't re-center it mid-animation.
    @State private var fullSize: CGSize?

    private var title: String { exercise?.exerciseName ?? "Review" }

    private var accessibilityText: String {
        guard let exercise, !isCompact else { return title }
        return "\(title), \(exercise.equipment.displayName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(isCompact ? .headline : .title3.weight(.semibold))
            if let exercise {
                // Stays in place and folds away, so it never sits outside the bubble mid-animation.
                Text(exercise.equipment.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .opacity(isCompact ? 0 : 1)
                    .frame(width: isCompact ? 0 : nil, height: isCompact ? 0 : nil, alignment: .top)
                    .clipped()
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isHeader)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if !isCompact { fullSize = size }
        }
        .frame(width: isCompact ? fullSize?.width : nil, height: isCompact ? fullSize?.height : nil)
        // Shrinks and grows in step with the bars' fade.
        .animation(IdleControls.fade, value: isCompact)
    }
}
