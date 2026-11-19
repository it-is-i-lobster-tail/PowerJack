//
//  WorkoutHeader.swift
//  PowerJack
//
//  The glass bubble at the top of a workout: the exercise on screen with its equipment under it.
//  While the bars fade away it steps down to the name alone, in a smaller font.
//  Between pages its width follows the swipe, from one exercise's bubble to the next.
//

import SwiftUI

struct WorkoutHeader: View {
    /// The exercise on screen. Nil on the Review page.
    let exercise: Exercise?
    /// True while the bars are faded: the name alone, smaller, in a smaller bubble.
    var isCompact = false
    /// The exercise on each page, nil for Review, and where the pages are scrolled to.
    var pages: [Exercise?] = []
    var pageScroll: ExercisePageScroll? = nil

    /// The full bubble's size. While compact, the header keeps taking up this much room and the
    /// bubble shrinks in the middle of it, so the navigation bar doesn't re-center it mid-animation.
    @State private var fullSize: CGSize?

    private var title: String { exercise?.exerciseName ?? "Review" }

    private var accessibilityText: String {
        guard let exercise, !isCompact else { return title }
        return "\(title), \(exercise.equipment.displayName)"
    }

    /// The pages on either side of a swipe, and how far it has gone from the first to the second.
    private var swipe: (from: Exercise?, to: Exercise?, progress: CGFloat)? {
        guard let pageScroll, pages.count > 1 else { return nil }
        let position = min(max(pageScroll.position, 0), CGFloat(pages.count - 1))
        let from = Int(position.rounded(.down))
        let progress = position - CGFloat(from)
        guard progress > 0.001, from + 1 < pages.count else { return nil }
        return (pages[from], pages[from + 1], progress)
    }

    var body: some View {
        SwipeWidthLayout(progress: swipe?.progress ?? 0) {
            HeaderLabel(exercise: exercise, isCompact: isCompact)
            // Laid out unseen, so the bubble can size itself between the two.
            if let swipe {
                HeaderLabel(exercise: swipe.from, isCompact: isCompact).hidden()
                HeaderLabel(exercise: swipe.to, isCompact: isCompact).hidden()
            }
        }
        .background { Color.clear.glassEffect(.powerJackBar, in: .capsule) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isHeader)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if !isCompact { fullSize = size }
        }
        .frame(width: isCompact ? fullSize?.width : nil, height: isCompact ? fullSize?.height : nil)
        .animation(IdleControls.fade, value: isCompact)
    }
}

/// The name, and the equipment under it unless compact, inside the bubble's padding.
private struct HeaderLabel: View {
    let exercise: Exercise?
    let isCompact: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(exercise?.exerciseName ?? "Review")
                .font(isCompact ? .headline : .title3.weight(.semibold))
            if let exercise {
                // Folded away in place rather than removed, so it shrinks into the bubble with it.
                Text(exercise.equipment.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .opacity(isCompact ? 0 : 1)
                    .frame(width: isCompact ? 0 : nil, height: isCompact ? 0 : nil, alignment: .top)
                    .clipped()
            }
        }
        .lineLimit(1)
        .allowsTightening(true)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Lays out the label at its own size. Mid-swipe it also measures both pages' labels, with the
/// room the navigation bar offers, and takes a width part way between them.
private struct SwipeWidthLayout: Layout {
    let progress: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let label = subviews.first else { return .zero }
        let size = label.sizeThatFits(proposal)
        guard subviews.count == 3 else { return size }
        let from = subviews[1].sizeThatFits(proposal).width
        let to = subviews[2].sizeThatFits(proposal).width
        return CGSize(width: from + (to - from) * progress, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Each at its own size, centered. Mid-swipe the name can run into the bubble's padding
        // for a moment rather than squeeze to fit.
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: proposal)
        }
    }
}
