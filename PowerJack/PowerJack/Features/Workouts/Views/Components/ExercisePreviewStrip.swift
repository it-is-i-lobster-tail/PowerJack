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

    @State private var stripPosition = ScrollPosition()
    @State private var stripPhase: ScrollPhase = .idle

    var body: some View {
        // Three whole cards fit on screen, so nothing is left half cut off.
        let spacing = LayoutMetrics.compactSpacing
        let cardWidth = max(0, (screenWidth - Self.edgeMargin * 2 - spacing * (Self.visibleCards - 1)) / Self.visibleCards)
        // One card's worth of room before the first card and after the last, so every card,
        // the first and last too, can sit in the middle.
        let sideMargin = Self.edgeMargin + cardWidth + spacing
        let step = cardWidth + spacing

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
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        // Cards the lifter scrolls to come to rest at the leading margin, which is the middle slot.
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition($stripPosition)
        .onScrollPhaseChange { _, newPhase in stripPhase = newPhase }
        // The side margins land after the first layout, so follow again whenever it changes.
        .onScrollGeometryChange(for: [CGFloat].self, of: Self.layoutKey) { _, _ in
            followPages(step: step, sideMargin: sideMargin)
        }
        // Frame by frame with the pages, so the strip moves with the lifter's finger.
        .onChange(of: pageScroll.position) { followPages(step: step, sideMargin: sideMargin) }
        .frame(height: 75)
        // The cards keep their size, so their names stop growing where they still fit.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Changes when the strip is laid out or resized, but not when it is scrolled.
    private static func layoutKey(_ geometry: ScrollGeometry) -> [CGFloat] {
        [geometry.contentSize.width, geometry.containerSize.width, geometry.contentInsets.leading]
    }

    /// Puts the card of the page on screen in the middle slot, and part way between two cards
    /// while a swipe is part way between two pages. A strip the lifter is scrolling is left alone.
    private func followPages(step: CGFloat, sideMargin: CGFloat) {
        guard stripPhase != .interacting, stripPhase != .decelerating else { return }
        // At rest the strip sits scrolled back by its leading margin, with the first card in the middle.
        stripPosition.scrollTo(x: pageScroll.position * step - sideMargin)
    }

    /// Selected is solid blue and full size, done exercises are tinted blue with a check, the rest
    /// stay plain. A card blends between the looks as its page swipes on or off the screen.
    private func card(_ title: String, index: Int, isDone: Bool, width: CGFloat) -> some View {
        // 1 while this card's page fills the screen, down to 0 a page away.
        let focus = max(0, 1 - abs(pageScroll.position - CGFloat(index)))
        let shape = RoundedRectangle(cornerRadius: LayoutMetrics.compactCornerRadius)

        return Button {
            selectExercise(at: index)
        } label: {
            ZStack {
                cardLabel(title, isDone: isDone, isSelected: false)
                    .opacity(1 - focus)
                cardLabel(title, isDone: isDone, isSelected: true)
                    .opacity(focus)
                    // The same name twice would be read twice.
                    .accessibilityHidden(true)
            }
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

    private func cardLabel(_ title: String, isDone: Bool, isSelected: Bool) -> some View {
        Text(title)
            .font(isSelected ? .default : .caption)
            .fontWeight(.medium)
            .foregroundStyle(isSelected ? Color.white : isDone ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        guard index != selectedExerciseIndex else {
            onReselect()
            return
        }
        withAnimation(.easeInOut(duration: 0.325)) {
            selectedExerciseIndex = index
        }
    }
}
