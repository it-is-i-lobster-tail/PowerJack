//
//  WorkoutHeader.swift
//  PowerJack
//
//  The glass bubble at the top of a workout: the exercise on screen with its equipment under it.
//  While the bars fade, the title steps down and only an active rest keeps its subtitle.
//  Between pages its width follows the swipe, from one exercise's bubble to the next.
//

import SwiftUI

struct WorkoutHeader: View {
    @Environment(\.workoutHeaderRest) private var rest

    /// The exercise on screen. Nil on the Review page.
    let exercise: Exercise?
    /// True while the controls are faded.
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
            HeaderLabel(exercise: exercise, isCompact: isCompact, rest: rest?.period, showsCountdown: true)
            // Laid out unseen, so the bubble can size itself between the two.
            if let swipe {
                HeaderLabel(exercise: swipe.from, isCompact: isCompact, rest: rest?.period).hidden()
                HeaderLabel(exercise: swipe.to, isCompact: isCompact, rest: rest?.period).hidden()
            }
        }
        .background { Color.clear.glassEffect(.powerJackBar, in: .capsule) }
        .contentShape(.capsule)
        .gesture(TapGesture().onEnded { rest?.onTap() }, isEnabled: rest != nil)
        .accessibilityElement(children: rest == nil ? .ignore : .combine)
        .accessibilityLabel(accessibilityText, isEnabled: rest == nil)
        .accessibilityAddTraits(rest == nil ? [] : .isButton)
        .accessibilityAddTraits(.isHeader)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if !isCompact { fullSize = size }
        }
        .frame(width: isCompact ? fullSize?.width : nil, height: isCompact ? fullSize?.height : nil)
        .animation(.easeInOut(duration: 0.18), value: rest != nil)
        .animation(IdleControls.fade, value: isCompact)
    }
}

/// Equipment and rest share one subtitle line. Only equipment folds away when idle.
private struct HeaderLabel: View {
    let exercise: Exercise?
    let isCompact: Bool
    let rest: RestPeriod?
    var showsCountdown = false

    private var foldsSubtitle: Bool { isCompact && rest == nil }

    var body: some View {
        VStack(spacing: 0) {
            Text(exercise?.exerciseName ?? "Review")
                .font(isCompact ? .callout.weight(.semibold) : .headline)
                .truncationMode(.tail)
            if exercise != nil || rest != nil {
                let equipment = exercise?.equipment.displayName ?? ""
                // The equipment's font metrics own this line, even when the ring is showing.
                ZStack {
                    Text(equipment.isEmpty ? " " : equipment)
                        .foregroundStyle(.secondary)
                        .opacity(rest == nil ? 1 : 0)
                        .accessibilityHidden(rest != nil || foldsSubtitle)
                    if let rest {
                        // Reserve the widest timer state once, including for swipe endpoint measurements.
                        ZStack {
                            Text("Rest " + Duration.seconds(Int(rest.duration.rounded(.up))).minuteSecondText)
                            Text("Start set")
                        }
                        .monospacedDigit()
                        .padding(.leading, 16)
                        .hidden()
                    }
                }
                .overlay {
                    if let rest, showsCountdown {
                        HeaderRestSubtitle(rest: rest)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .font(.subheadline)
                .fixedSize()
                .opacity(foldsSubtitle ? 0 : 1)
                .frame(width: foldsSubtitle ? 0 : nil, height: foldsSubtitle ? 0 : nil, alignment: .top)
                .clipped()
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, isCompact ? 6 : 8)
    }
}

private struct HeaderRestSubtitle: View {
    let rest: RestPeriod

    var body: some View {
        TimelineView(.periodic(from: rest.startedAt, by: 1)) { context in
            let date = context.date.addingTimeInterval(0.05)
            let ready = !rest.isResting(at: date)
            let seconds = Int(rest.remaining(at: date).rounded(.up))
            HStack(spacing: 4) {
                RestIslandRing(fractionRemaining: rest.fractionRemaining(at: date), isReady: ready, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text(ready ? "Start set" : "Rest " + Duration.seconds(seconds).minuteSecondText)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.16), value: seconds)
            }
            .foregroundStyle(ready ? Color.green : .orange)
            .animation(.easeInOut(duration: 0.18), value: ready)
        }
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
