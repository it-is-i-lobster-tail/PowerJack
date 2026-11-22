//
//  WorkoutHeader.swift
//  PowerJack
//
//  The workout header always shows the page's exercise name and equipment.
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
    let pageScroll: ExercisePageScroll

    private var position: CGFloat {
        min(max(0, pageScroll.position), CGFloat(max(0, pages.count - 1)))
    }

    private var visiblePage: WorkoutPageHeader {
        pages.isEmpty ? .review : pages[Int(position.rounded(.toNearestOrEven))]
    }

    private var pageLabel: String {
        [visiblePage.title, visiblePage.superset.map { SupersetStyle.fullLabel(partners: $0.partners) }, visiblePage.equipment]
            .compactMap(\.self)
            .joined(separator: ", ")
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
                HeaderLabel(page: pages[index], rest: rest?.period)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            pill.fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeInOut(duration: 0.18), value: rest != nil)
    }

    private var pill: some View {
        let swipe = swipe
        return SwipeWidthLayout(progress: swipe?.progress ?? 0) {
            HeaderLabel(page: visiblePage, rest: rest?.period, showsCountdown: swipe == nil, showsPageText: swipe == nil)
            // Mid-swipe each page carries its own timer, so it slides with that page's superset tag.
            if let swipe {
                HeaderLabel(page: swipe.from, rest: rest?.period, showsCountdown: true)
                    .accessibilityHidden(true)
                HeaderLabel(page: swipe.to, rest: rest?.period, showsCountdown: true)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.capsule)
        .background { Color.clear.glassEffect(.powerJackBar, in: .capsule) }
        .contentShape(.capsule)
        .gesture(TapGesture().onEnded { rest?.onTap() }, isEnabled: rest != nil)
        .accessibilityElement(children: rest == nil ? .ignore : .combine)
        .accessibilityLabel(pageLabel, isEnabled: rest == nil)
        .accessibilityAddTraits(rest == nil ? [] : .isButton)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The exercise name, then a line with its superset and equipment. A running rest timer takes the
/// equipment's place. The superset is in the color of its bar.
private struct HeaderLabel: View {
    let page: WorkoutPageHeader
    let rest: RestPeriod?
    var showsCountdown = false
    var showsPageText = true

    var body: some View {
        VStack(spacing: 0) {
            Text(page.title)
                .font(.headline)
                .minimumScaleFactor(0.01)
                .opacity(showsPageText ? 1 : 0)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let superset = page.superset {
                    Label(superset.title, systemImage: "link")
                        .labelStyle(.titleAndIcon)
                        // A touch smaller than the equipment, so it reads as a tag.
                        .font(.footnote)
                        .foregroundStyle(superset.color)
                        .opacity(showsPageText ? 1 : 0)
                        .accessibilityLabel(SupersetStyle.fullLabel(partners: superset.partners))
                }
                detail
            }
            .font(.subheadline)
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// The equipment, or a running rest timer in its place.
    @ViewBuilder
    private var detail: some View {
        if let rest {
            // Measure the widest countdown state, so the label keeps its width as the seconds change.
            ZStack {
                Text("Rest " + Duration.seconds(Int(rest.duration.rounded(.up))).minuteSecondText)
                Text("Start set")
            }
            .monospacedDigit()
            .padding(.leading, 16)
            .hidden()
            .overlay {
                if showsCountdown { HeaderRestSubtitle(rest: rest).fixedSize() }
            }
        } else if let equipment = page.equipment {
            Text(equipment)
                .foregroundStyle(.secondary)
                .opacity(showsPageText ? 1 : 0)
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
