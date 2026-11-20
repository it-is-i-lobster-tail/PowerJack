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
}

struct ExercisePreviewStrip: View {
    let pages: [WorkoutPage]
    let screenWidth: CGFloat
    /// Adds a Review card after the last exercise.
    var showsReview = false
    /// Where the pages are. The strip slides, recolors and resizes its cards along with them.
    let pageScroll: ExercisePageScroll
    private static let visibleCards: CGFloat = 3
    private static let edgeMargin: CGFloat = 16
    private static let cardHeight: CGFloat = 58
    /// How big the other cards are next to the selected one.
    private static let restingScale: CGFloat = 0.78
    @Binding var selectedPageIndex: Int?
    /// Tapping the exercise already selected, so the pages can come back to it.
    var onReselect: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var stripPosition = ScrollPosition()
    private let spacing = LayoutMetrics.compactSpacing

    /// A drag on the strip settles on a card. A drag on the pager can stop between cards.
    private var isBrowsingStrip: Bool {
        switch pageScroll.stripPhase {
        case .tracking, .interacting, .decelerating: true
        default: false
        }
    }

    /// Three whole cards fit on screen, so nothing is left half cut off.
    private var cardWidth: CGFloat {
        max(0, (screenWidth - Self.edgeMargin * 2 - spacing * (Self.visibleCards - 1)) / Self.visibleCards)
    }

    /// From one card to the next.
    private var step: CGFloat { cardWidth + spacing }

    var body: some View {
        // One card's worth of room before the first card and after the last, so every card,
        // the first and last too, can sit in the middle.
        let sideMargin = Self.edgeMargin + cardWidth + spacing

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(pages.indices, id: \.self) { index in
                    let page = pages[index]
                    card(page.header.title, index: index, isDone: page.exercises.allSatisfy(\.isDone),
                         width: cardWidth, count: page.letter == nil ? nil : page.exercises.count)
                }

                if showsReview {
                    card("Review", index: pages.count, isDone: false, width: cardWidth)
                }
            }
            .scrollTargetLayout(isEnabled: isBrowsingStrip)
            .padding(.vertical, LayoutMetrics.compactSpacing)
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
                selectedPageIndex = index
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
        .frame(height: 75)
        // The cards keep their size, so their names stop growing where they still fit.
        // `textScale` caps at the same size.
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
        let last = max(0, pages.count - (showsReview ? 0 : 1))
        let offset = geometry.contentOffset.x + geometry.contentInsets.leading
        return min(max(0, offset / step), CGFloat(last))
    }

    /// Selected is solid blue and full size, done exercises are tinted blue with a check, the rest
    /// stay plain. A card blends between the looks as its page swipes on or off the screen.
    private func card(_ title: String, index: Int, isDone: Bool, width: CGFloat, count: Int? = nil) -> some View {
        let focus = Self.focus(ofCard: index, pagePosition: pageScroll.position)
        let shape = RoundedRectangle(cornerRadius: LayoutMetrics.compactCornerRadius)

        return Button {
            selectExercise(at: index)
        } label: {
            cardLabel(title, count: count, isDone: isDone, isSelected: focus >= 0.5, textScale: Self.textScale(focus: focus, dynamicTypeSize: dynamicTypeSize))
                // The name changes color halfway, where the two cards are the same size. Blending it
                // along the way would fade it into the blue.
                .animation(.easeInOut(duration: 0.2), value: focus >= 0.5)
                .frame(width: width + spacing, height: Self.cardHeight)
                .background {
                    shape.fill(isDone ? Color.accentColor.opacity(VisualOpacity.light) : Color.gray.opacity(VisualOpacity.subtle))
                    shape.fill(Color.accentColor).opacity(focus)
                }
                .scaleEffect(Self.restingScale + (1 - Self.restingScale) * focus)
        }
        // Keep the snap targets equally spaced as the visible cards grow and shrink.
        .frame(width: width)
        .accessibilityValue(isDone ? "Done" : "")
        .id(index)
    }

    /// How selected a card looks: 1 while its page fills the screen, down to 0 a page away.
    static func focus(ofCard index: Int, pagePosition: CGFloat) -> CGFloat {
        max(0, 1 - abs(pagePosition - CGFloat(index)))
    }

    /// How big a card's name is next to the selected card's: caption size a page away, callout size on
    /// its page, and smoothly between while the pages swipe.
    static func textScale(focus: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let sizes = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(min(dynamicTypeSize, .xxxLarge)))
        let caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: sizes).pointSize
        let callout = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: sizes).pointSize
        let resting = caption / callout
        return resting + (1 - resting) * focus
    }

    private func cardLabel(_ title: String, count: Int?, isDone: Bool, isSelected: Bool, textScale: CGFloat) -> some View {
        // One font laid out at the full card size, then scaled, so the name grows with the card
        // and wraps the same way all through a swipe.
        VStack(spacing: 1) {
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(3)
                .minimumScaleFactor(0.01)
                .multilineTextAlignment(.center)
            if let count {
                Text("\(count) exercises").font(.caption).lineLimit(1)
            }
        }
            .foregroundStyle(isSelected ? Color.white : isDone ? Color.accentColor : Color.primary)
            .padding(.horizontal, isDone ? 15 : 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(textScale)
            // Done is marked with more than color.
            .overlay(alignment: .topTrailing) {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
    }

    private func selectExercise(at index: Int) {
        withAnimation(.easeInOut(duration: 0.325)) {
            pageScroll.isDrivenByStrip = false
            if index == selectedPageIndex {
                onReselect()
            } else {
                selectedPageIndex = index
            }
        }
    }
}
