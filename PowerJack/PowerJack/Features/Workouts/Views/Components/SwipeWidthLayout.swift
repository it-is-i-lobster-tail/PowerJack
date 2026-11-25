import SwiftUI

/// Lays out the label at its own size. Mid-swipe it also measures both pages' labels, with the
/// room the navigation bar offers, and takes a width part way between them.
struct SwipeWidthLayout: Layout {
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
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        subviews.first?.place(at: center, anchor: .center, proposal: proposal)
        guard subviews.count == 3 else { return }

        // Move complete labels through the capsule like the pages beneath them. Its
        // interpolated width must never become a line-breaking constraint for either name.
        let from = subviews[1]
        let to = subviews[2]
        let distance = (from.sizeThatFits(proposal).width + to.sizeThatFits(proposal).width) / 2
        from.place(at: CGPoint(x: center.x - progress * distance, y: center.y),
                   anchor: .center, proposal: proposal)
        to.place(at: CGPoint(x: center.x + (1 - progress) * distance, y: center.y),
                 anchor: .center, proposal: proposal)
    }
}
