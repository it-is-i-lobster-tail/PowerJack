//
//  WorkoutHeader.swift
//  PowerJack
//
//  The workout header picks up the page title as the preview cards fade.
//  Between pages its width follows the swipe, from one exercise's bubble to the next.
//

import SwiftUI

/// The superset an exercise page belongs to, shown in the pill in the color of its bar.
struct WorkoutPageSuperset {
    let letter: String
    let color: Color
    let partners: [String]

    init(letter: String, color: Color, partners: [String]) {
        self.letter = letter
        self.color = color
        self.partners = partners
    }

    init?(_ workoutExercise: WorkoutExercise) {
        guard let index = workoutExercise.supersetIndex else { return nil }
        self.init(letter: Workout.supersetLetter(at: index),
                  color: SupersetStyle.color(at: index),
                  partners: workoutExercise.supersetPartners.compactMap { $0.shownExercise?.exerciseName })
    }

    /// e.g. "Superset A".
    var title: String { "Superset \(letter)" }
}

enum WorkoutPageHeader {
    case exercise(Exercise?, superset: WorkoutPageSuperset? = nil), review

    var title: String {
        switch self {
        case .exercise(let exercise, _): exercise?.exerciseName ?? "Exercise"
        case .review: "Review"
        }
    }

    var equipment: String? {
        if case .exercise(let exercise, _) = self { return exercise?.equipment.displayName }
        return nil
    }

    var superset: WorkoutPageSuperset? {
        if case .exercise(_, let superset) = self { return superset }
        return nil
    }
}

struct WorkoutHeader: View {
    @Environment(\.workoutHeaderRest) private var rest

    let pages: [WorkoutPageHeader]
    let controlsHidden: Bool
    let pageScroll: ExercisePageScroll
    var idleWidth: CGFloat?

    private var position: CGFloat {
        min(max(0, pageScroll.position), CGFloat(max(0, pages.count - 1)))
    }

    private var visiblePage: WorkoutPageHeader {
        pages.isEmpty ? .review : pages[Int(position.rounded(.toNearestOrEven))]
    }

    private var idleLabel: String {
        guard let equipment = visiblePage.equipment else { return visiblePage.title }
        let detail = [visiblePage.superset.map { SupersetStyle.fullLabel(partners: $0.partners) }, equipment]
            .compactMap(\.self)
            .joined(separator: ", ")
        return controlsHidden ? "\(visiblePage.title), \(detail)" : detail
    }

    /// The pages on either side of a swipe, and how far it has gone from the first to the second.
    private var swipe: (from: WorkoutPageHeader, to: WorkoutPageHeader, progress: CGFloat)? {
        guard pages.count > 1 else { return nil }
        let from = Int(position.rounded(.down))
        let progress = position - CGFloat(from)
        guard progress > 0.001, from + 1 < pages.count else { return nil }
        return (pages[from], pages[from + 1], progress)
    }

    var body: some View {
        ZStack {
            // Reserve the widest page title before the swipe starts. The toolbar can still
            // constrain long titles to the space between its leading and trailing buttons.
            ForEach(pages.indices, id: \.self) { index in
                // Reserve room for both idle states, so the toolbar stays centered as its contents change.
                ForEach([false, true], id: \.self) { hidden in
                    HeaderLabel(page: pages[index], controlsHidden: hidden, rest: rest?.period)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        }
        .overlay {
            // Keep the toolbar's center anchor while letting the idle title use the faded buttons' space.
            pill
                .frame(width: controlsHidden ? idleWidth : nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeInOut(duration: 0.18), value: rest != nil)
        .animation(IdleControls.fade, value: controlsHidden)
    }

    private var pill: some View {
        let swipe = swipe
        return SwipeWidthLayout(progress: swipe?.progress ?? 0) {
            HeaderLabel(page: visiblePage, controlsHidden: controlsHidden, rest: rest?.period,
                        showsCountdown: true, showsPageText: swipe == nil)
            if let swipe {
                HeaderLabel(page: swipe.from, controlsHidden: controlsHidden, rest: rest?.period)
                    .accessibilityHidden(true)
                HeaderLabel(page: swipe.to, controlsHidden: controlsHidden, rest: rest?.period)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.capsule)
        .background { Color.clear.glassEffect(.powerJackBar, in: .capsule) }
        .contentShape(.capsule)
        .gesture(TapGesture().onEnded { rest?.onTap() }, isEnabled: rest != nil)
        .accessibilityElement(children: rest == nil ? .ignore : .combine)
        .accessibilityLabel(idleLabel, isEnabled: rest == nil)
        .accessibilityAddTraits(rest == nil ? [] : .isButton)
        .accessibilityAddTraits(.isHeader)
    }
}

/// When the cards fade the pill takes over their title. Its second line reads superset, equipment,
/// then any running rest timer. The superset is in the color of its bar.
private struct HeaderLabel: View {
    let page: WorkoutPageHeader
    let controlsHidden: Bool
    let rest: RestPeriod?
    var showsCountdown = false
    var showsPageText = true

    private var showsTitle: Bool {
        if case .review = page { return true }
        return controlsHidden || (rest == nil && page.equipment == nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsTitle {
                Text(page.title)
                    .font(.headline)
                    .minimumScaleFactor(0.01)
                    .opacity(showsPageText ? 1 : 0)
            }
            HStack(spacing: 8) {
                if let superset = page.superset {
                    // While resting the line also holds the timer, so the superset shortens to its letter.
                    Label(rest == nil ? superset.title : superset.letter, systemImage: "link")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(superset.color)
                        .opacity(showsPageText ? 1 : 0)
                        .accessibilityLabel(SupersetStyle.fullLabel(partners: superset.partners))
                }
                detail
            }
            .font(controlsHidden ? .subheadline : .headline)
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, controlsHidden ? 6 : 8)
    }

    @ViewBuilder
    /// The equipment, then a running rest timer to its right.
    private var detail: some View {
        if let equipment = page.equipment {
            Text(equipment)
                .foregroundStyle(controlsHidden ? Color.secondary : .primary)
                .opacity(showsPageText ? 1 : 0)
        }
        if let rest {
            // Measure the widest countdown state without creating a live timer per swipe endpoint.
            ZStack {
                Text("Rest " + Duration.seconds(Int(rest.duration.rounded(.up))).minuteSecondText)
                Text("Start set")
            }
            .monospacedDigit()
            .padding(.leading, 16)
            .hidden()
            .overlay(alignment: .leading) {
                if showsCountdown { HeaderRestSubtitle(rest: rest).fixedSize() }
            }
        }
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
