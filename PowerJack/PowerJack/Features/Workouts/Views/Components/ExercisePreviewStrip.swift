//
//  ExercisePreviewStrip.swift
//  PowerJack
//
//  Created on 6/26/26.
//

import SwiftUI

/// How far the exercise pages have scrolled, counted in pages: 1.5 is halfway from the second page
/// to the third. The strip follows it so it slides with the lifter's finger. It lives in its own
/// object so only the strip redraws while the pages move.
@Observable
final class ExercisePageScroll {
    var position: CGFloat = 0
}

struct ExercisePreviewStrip: View {
    let workoutExercises: [WorkoutExercise]
    let screenWidth: CGFloat
    /// Adds a Review card after the last exercise.
    var showsReview = false
    /// Where the pages are. The strip slides, recolors and resizes its cards along with them.
    let pageScroll: ExercisePageScroll
    private static let visibleCards: CGFloat = 3
    private static let edgeMargin: CGFloat = 16
    private static let cardHeight: CGFloat = 54
    /// How big the other cards are next to the selected one.
    private static let restingScale: CGFloat = 0.88
    /// Space between a superset's cards and the line under them.
    private static let underlineGap: CGFloat = 6

    @Binding var selectedExerciseIndex: Int?
    /// Tapping the exercise already selected, so the pages can come back to it.
    var onReselect: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var stripPosition = ScrollPosition()
    @State private var stripPhase: ScrollPhase = .idle
    /// The card the lifter tapped, while the pages glide over to it. The strip glides there from
    /// where it is, instead of following the pages, which would first pull it back to the page on screen.
    @State private var glideTarget: Int?

    private let spacing = LayoutMetrics.compactSpacing

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
                ForEach(workoutExercises.indices, id: \.self) { index in
                    card(
                        workoutExercises[index].shownExercise?.exerciseName ?? "",
                        index: index,
                        isDone: workoutExercises[index].isDone,
                        width: cardWidth
                    )
                    .overlay(alignment: .bottomLeading) {
                        supersetUnderline(from: index, cardWidth: cardWidth, spacing: spacing)
                    }
                }

                if showsReview {
                    card("Review", index: workoutExercises.count, isDone: false, width: cardWidth)
                }
            }
            // Room for the superset line, which the scroll view would clip.
            .padding(.vertical, Self.underlineGap + 2)
        }
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        // Cards the lifter flicks to come to rest in the middle slot.
        .scrollTargetBehavior(CardSnap(step: step))
        .scrollPosition($stripPosition)
        .onScrollPhaseChange { _, newPhase in stripPhase = newPhase }
        // The side margins land after the first layout, so follow again whenever it changes.
        .onScrollGeometryChange(for: [CGFloat].self, of: Self.layoutKey) { _, _ in
            followPages()
        }
        // Frame by frame with the pages, so the strip moves with the lifter's finger.
        .onChange(of: pageScroll.position) { followPages() }
        .frame(height: 75)
        // The cards keep their size, so their names stop growing where they still fit.
        // `textScale` caps at the same size.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Changes when the strip is laid out or resized, but not when it is scrolled.
    private static func layoutKey(_ geometry: ScrollGeometry) -> [CGFloat] {
        [geometry.contentSize.width, geometry.containerSize.width, geometry.contentInsets.leading]
    }

    /// Puts the card of the page on screen in the middle slot, and part way between two cards
    /// while a swipe is part way between two pages. A strip the lifter is scrolling is left alone.
    private func followPages() {
        guard stripPhase != .interacting, stripPhase != .decelerating else { return }
        if let glideTarget {
            let pagesArrived = abs(pageScroll.position - CGFloat(glideTarget)) < 0.01
            // Swiping to another page mid-glide hands the strip back to the pages.
            guard pagesArrived || selectedExerciseIndex != glideTarget else { return }
            self.glideTarget = nil
        }
        // Offsets count from the first card resting in the middle slot, inside the leading margin.
        stripPosition.scrollTo(x: pageScroll.position * step)
    }

    /// Selected is solid blue and full size, done exercises are tinted blue with a check, the rest
    /// stay plain. A card blends between the looks as its page swipes on or off the screen.
    private func card(_ title: String, index: Int, isDone: Bool, width: CGFloat) -> some View {
        let focus = Self.focus(ofCard: index, pagePosition: pageScroll.position)
        let shape = RoundedRectangle(cornerRadius: LayoutMetrics.compactCornerRadius)

        return Button {
            selectExercise(at: index)
        } label: {
            cardLabel(title, isDone: isDone, isSelected: focus >= 0.5, textScale: Self.textScale(focus: focus, dynamicTypeSize: dynamicTypeSize))
                // The name changes color halfway, where the two cards are the same size. Blending it
                // along the way would fade it into the blue.
                .animation(.easeInOut(duration: 0.2), value: focus >= 0.5)
                .frame(width: width, height: Self.cardHeight)
                .background {
                    shape.fill(isDone ? Color.accentColor.opacity(VisualOpacity.light) : Color.gray.opacity(VisualOpacity.subtle))
                    shape.fill(Color.accentColor).opacity(focus)
                }
                .scaleEffect(Self.restingScale + (1 - Self.restingScale) * focus)
        }
        .accessibilityValue(isDone ? "Done" : "")
        .accessibilityHint(workoutExercises.indices.contains(index) && !workoutExercises[index].supersetPartners.isEmpty ? "Superset" : "")
        .id(index)
    }

    /// How selected a card looks: 1 while its page fills the screen, down to 0 a page away.
    static func focus(ofCard index: Int, pagePosition: CGFloat) -> CGFloat {
        max(0, 1 - abs(pagePosition - CGFloat(index)))
    }

    /// How big a card's name is next to the selected card's: caption size a page away, body size on
    /// its page, and smoothly between while the pages swipe.
    static func textScale(focus: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let sizes = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(min(dynamicTypeSize, .xxxLarge)))
        let caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: sizes).pointSize
        let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: sizes).pointSize
        let resting = caption / body
        return resting + (1 - resting) * focus
    }

    private func cardLabel(_ title: String, isDone: Bool, isSelected: Bool, textScale: CGFloat) -> some View {
        // One font laid out at the full card size, then scaled, so the name grows with the card
        // and wraps the same way all through a swipe.
        Text(title)
            .font(.body)
            .fontWeight(.medium)
            .foregroundStyle(isSelected ? Color.white : isDone ? Color.accentColor : Color.primary)
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

    /// One line under all of a superset's cards, drawn from its first card.
    @ViewBuilder
    private func supersetUnderline(from index: Int, cardWidth: CGFloat, spacing: CGFloat) -> some View {
        let workoutExercise = workoutExercises[index]
        let partners = workoutExercise.supersetPartners
        if !partners.isEmpty, index == 0 || !partners.contains(where: { $0 === workoutExercises[index - 1] }) {
            let count = CGFloat(partners.count + 1)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: cardWidth * count + spacing * (count - 1), height: 3)
                .offset(y: Self.underlineGap)
                .accessibilityHidden(true)
        }
    }

    private func selectExercise(at index: Int) {
        withAnimation(.easeInOut(duration: 0.325)) {
            glideTarget = index
            stripPosition.scrollTo(x: CGFloat(index) * step)
            if index == selectedExerciseIndex {
                onReselect()
            } else {
                selectedExerciseIndex = index
            }
        }
    }
}

/// Ends a flick of the strip with a card in the middle slot. Unlike `.viewAligned`, it leaves scrolls
/// with no speed alone: those are the strip following the pages, which can rest between two cards
/// while a swipe is between two pages.
private struct CardSnap: ScrollTargetBehavior {
    let step: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard context.velocity.dx != 0, step > 0 else { return }
        target.rect.origin.x = (target.rect.minX / step).rounded() * step
    }
}
