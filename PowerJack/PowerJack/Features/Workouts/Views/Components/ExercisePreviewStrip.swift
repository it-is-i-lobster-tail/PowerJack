//
//  ExercisePreviewStrip.swift
//  PowerJack
//
//  Created on 6/26/26.
//

import SwiftUI

/// The active scroller publishes a fractional exercise index for both scrollers and the header.
@Observable
final class ExercisePageScroll {
    var position: CGFloat = 0
    var isDrivenByStrip = false
    var stripPhase: ScrollPhase = .idle
    /// The page the finger left, retained through deceleration so a reversed drag can unwind the reveal.
    var swipeStartPage: Int?

    func swipeOffset(lastPage: Int) -> CGFloat {
        guard let swipeStartPage else { return 0 }
        let page = min(max(position, 0), CGFloat(lastPage))
        return min(1, max(-1, page - CGFloat(swipeStartPage)))
    }
}

struct ExercisePreviewStrip: View {
    let workoutExercises: [WorkoutExercise]
    let screenWidth: CGFloat
    /// Adds a Review card after the last exercise.
    var showsReview = false
    /// Where the pages are. The strip slides, recolors and resizes its cards along with them.
    let pageScroll: ExercisePageScroll
    private static let edgeFade: CGFloat = 64
    private static let restingHeight: CGFloat = 54
    private static let focusedHeight: CGFloat = 64
    private static let previewNameLength = 20
    private static let neighborShift: CGFloat = 9
    /// Space between a superset's cards and the line under them.
    private static let underlineGap: CGFloat = 6

    @Binding var selectedExerciseIndex: Int?
    /// Tapping the exercise already selected, so the pages can come back to it.
    var onReselect: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var stripPosition = ScrollPosition()
    private let spacing = LayoutMetrics.compactSpacing

    /// A drag on the strip settles on a card. A drag on the pager can stop between cards.
    private var isBrowsingStrip: Bool {
        switch pageScroll.stripPhase {
        case .tracking, .interacting, .decelerating: true
        default: false
        }
    }

    /// The second neighbor is centered just inside each edge, leaving part of it offscreen.
    private var step: CGFloat { max(spacing, screenWidth * 0.238) }
    private var slotWidth: CGFloat { step - spacing }
    private var horizontalDirection: CGFloat { layoutDirection == .leftToRight ? 1 : -1 }

    var body: some View {
        // The first and last cards also need room to center their slots.
        let sideMargin = max(0, (screenWidth - slotWidth) / 2)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(workoutExercises.indices, id: \.self) { index in
                    let exercise = workoutExercises[index]
                    card(exercise.shownExercise?.exerciseName ?? "Exercise", index: index, isDone: exercise.isDone)
                        .accessibilityHint(exercise.supersetPartners.isEmpty ? "" : "Superset")
                        .overlay(alignment: .bottomLeading) {
                            supersetUnderline(from: index)
                        }
                }

                if showsReview {
                    card("Review", index: workoutExercises.count, isDone: false)
                }
            }
            .scrollTargetLayout(isEnabled: isBrowsingStrip)
            // Room for the superset line, which the scroll view would clip.
            .padding(.vertical, Self.underlineGap + 2)
        }
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        // Cards the lifter flicks to come to rest in the middle slot.
        .scrollTargetBehavior(.viewAligned(anchor: .center))
        .scrollPosition($stripPosition)
        .onScrollPhaseChange { oldPhase, newPhase, context in
            pageScroll.stripPhase = newPhase
            if newPhase == .interacting {
                pageScroll.isDrivenByStrip = true
            }
            guard pageScroll.isDrivenByStrip else { return }
            if newPhase == .idle, oldPhase == .interacting || oldPhase == .decelerating {
                let index = Int(cardPosition(context.geometry).rounded())
                pageScroll.position = CGFloat(index)
                selectedExerciseIndex = index
            }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: cardPosition) { _, position in
            if pageScroll.isDrivenByStrip && isBrowsingStrip {
                pageScroll.position = position
            }
        }
        // The side margins land after the first layout, so follow again whenever it changes.
        .onScrollGeometryChange(for: [CGFloat].self, of: Self.layoutKey) { _, _ in
            if !isBrowsingStrip { followPages() }
        }
        // Frame by frame with the pages, so the strip moves with the lifter's finger.
        .onChange(of: pageScroll.position) {
            if !pageScroll.isDrivenByStrip { followPages() }
        }
        .mask {
            GeometryReader { geometry in
                let fade = min(0.16, Self.edgeFade / max(1, geometry.size.width))
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: fade),
                        .init(color: .black, location: 1 - fade),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .frame(height: Self.focusedHeight + (Self.underlineGap + 2) * 2)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Changes when the strip is laid out or resized, but not when it is scrolled.
    private nonisolated static func layoutKey(_ geometry: ScrollGeometry) -> [CGFloat] {
        [geometry.contentSize.width, geometry.containerSize.width, geometry.contentInsets.leading]
    }

    /// Puts the card of the page on screen in the middle slot, and part way between two cards
    /// while a swipe is part way between two pages. A strip the lifter is scrolling is left alone.
    private func followPages() {
        // Offsets count from the first card resting in the middle slot, inside the leading margin.
        stripPosition.scrollTo(x: pageScroll.position * step)
    }

    private func cardPosition(_ geometry: ScrollGeometry) -> CGFloat {
        let last = max(0, workoutExercises.count - (showsReview ? 0 : 1))
        let offset = geometry.contentOffset.x + geometry.contentInsets.leading
        return min(max(0, offset / step), CGFloat(last))
    }

    /// Selected is solid blue and full size, done exercises are tinted blue with a check, the rest
    /// stay plain. A card blends between the looks as its page swipes on or off the screen.
    private func card(_ title: String, index: Int, isDone: Bool) -> some View {
        let focus = Self.focus(ofCard: index, pagePosition: pageScroll.position)
        let isSelected = focus >= 0.5
        let height = Self.restingHeight + (Self.focusedHeight - Self.restingHeight) * focus
        let shape = RoundedRectangle(cornerRadius: LayoutMetrics.compactCornerRadius)

        return Button {
            selectExercise(at: index)
        } label: {
            cardLabel(title, isDone: isDone, isSelected: isSelected, focus: focus)
                // The name changes color halfway, where the two cards are the same size. Blending it
                // along the way would fade it into the blue.
                .animation(.easeInOut(duration: 0.2), value: isSelected)
                .frame(width: cardWidth(focus: focus), height: height)
                .background {
                    shape.fill(isDone ? Color.accentColor.opacity(VisualOpacity.light) : Color.gray.opacity(VisualOpacity.subtle))
                    shape.fill(Color.accentColor).opacity(focus)
                }
                .contentShape(.rect)
        }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(isDone ? "Done" : "")
        .offset(x: cardOffset(at: index) * horizontalDirection)
        // The faces move within fixed slots so the pager and scroll targets stay in sync.
        .frame(width: slotWidth, height: Self.focusedHeight)
        .id(index)
    }

    private func cardWidth(focus: CGFloat) -> CGFloat {
        max(0, slotWidth - 12 + 30 * focus)
    }

    /// Move the immediate neighbors toward the outer cards, even between pages during a swipe.
    private func cardOffset(at index: Int) -> CGFloat {
        let distance = CGFloat(index) - pageScroll.position
        let weight = max(0, 1 - abs(abs(distance) - 1))
        return Self.neighborShift * weight * (distance < 0 ? -1 : 1)
    }

    /// How selected a card looks: 1 while its page fills the screen, down to 0 a page away.
    static func focus(ofCard index: Int, pagePosition: CGFloat) -> CGFloat {
        max(0, 1 - abs(pagePosition - CGFloat(index)))
    }

    /// How big a card's name is next to the selected card's: caption size a page away, callout size on
    /// its page, and smoothly between while the pages swipe.
    static func textScale(focus: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let sizes = typeTraits(dynamicTypeSize)
        let caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: sizes).pointSize
        let callout = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: sizes).pointSize
        let resting = caption / callout
        return resting + (1 - resting) * focus
    }

    private static func typeTraits(_ size: DynamicTypeSize) -> UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(min(size, .xxxLarge)))
    }

    private func cardLabel(_ title: String, isDone: Bool, isSelected: Bool, focus: CGFloat) -> some View {
        let calloutSize = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: Self.typeTraits(dynamicTypeSize)).pointSize
        let pointSize = calloutSize * Self.textScale(focus: focus, dynamicTypeSize: dynamicTypeSize)
        let titleText = Text(verbatim: title)
        let fittedTitle = !isSelected && title.count > Self.previewNameLength
            ? Text(verbatim: String(title.prefix(Self.previewNameLength)) + "…")
            : titleText

        return ViewThatFits(in: .vertical) {
            titleText.fixedSize(horizontal: false, vertical: true)
            // Long words and wide characters may need smaller type to fit the card.
            fittedTitle.lineLimit(3).minimumScaleFactor(0.25)
        }
            .font(.system(size: pointSize, weight: isSelected ? .semibold : .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(isSelected ? Color.white : isDone ? Color.accentColor : Color.primary)
            .padding(.horizontal, 4)
            .padding(.top, isDone ? 11 : 0)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Done is marked with more than color.
            .overlay(alignment: .topTrailing) {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
    }

    /// One line in the superset's color under all of its cards, drawn from its first card.
    @ViewBuilder
    private func supersetUnderline(from index: Int) -> some View {
        let workoutExercise = workoutExercises[index]
        let partners = workoutExercise.supersetPartners
        if !partners.isEmpty, index == 0 || !partners.contains(where: { $0 === workoutExercises[index - 1] }) {
            let firstWidth = cardWidth(focus: Self.focus(ofCard: index, pagePosition: pageScroll.position))
            let lastIndex = index + partners.count
            let lastWidth = cardWidth(focus: Self.focus(ofCard: lastIndex, pagePosition: pageScroll.position))
            let firstOffset = cardOffset(at: index)
            let span = step * CGFloat(partners.count) + cardOffset(at: lastIndex) - firstOffset
            Capsule()
                .fill(workoutExercise.supersetColor ?? .accentColor)
                .frame(width: span + (firstWidth + lastWidth) / 2, height: 3)
                .offset(x: ((slotWidth - firstWidth) / 2 + firstOffset) * horizontalDirection, y: Self.underlineGap)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func selectExercise(at index: Int) {
        withAnimation(.easeInOut(duration: 0.325)) {
            pageScroll.isDrivenByStrip = false
            if index == selectedExerciseIndex {
                onReselect()
            } else {
                selectedExerciseIndex = index
            }
        }
    }
}
