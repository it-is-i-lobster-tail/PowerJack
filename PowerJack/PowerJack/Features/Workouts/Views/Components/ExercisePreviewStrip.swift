//
//  ExercisePreviewStrip.swift
//  PowerJack
//
//  Created by Brendon on 6/26/26.
//

import SwiftUI

struct ExercisePreviewStrip: View {
    let workoutExercises: [WorkoutExercise]
    let screenWidth: CGFloat
    /// Adds a Review card after the last exercise.
    var showsReview = false
    private static let visibleCards: CGFloat = 3
    private static let edgeMargin: CGFloat = 16
    /// Space between a superset's cards and the line under them.
    private static let underlineGap: CGFloat = 6

    @Binding var selectedExerciseIndex: Int?

    var body: some View {
        // Three whole cards fit on screen, so nothing is left half cut off.
        let spacing = LayoutMetrics.compactSpacing
        let cardWidth = max(0, (screenWidth - Self.edgeMargin * 2 - spacing * (Self.visibleCards - 1)) / Self.visibleCards)

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(workoutExercises.indices, id: \.self) { index in
                        card(
                            workoutExercises[index].exercise?.exerciseName ?? "",
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
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Self.edgeMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            // Center the restored exercise when a workout reopens mid-way. This waits for the layout
            // to settle: the edge margins land after onAppear and reset the strip to its start.
            // The stack is not lazy, so every card exists to scroll to while the strip lays out.
            .onScrollGeometryChange(for: [CGFloat].self, of: Self.layoutKey) { _, _ in
                guard let selectedExerciseIndex else { return }
                proxy.scrollTo(selectedExerciseIndex, anchor: .center)
            }
            // Quick taps can cut a scroll short. Once it stops, center the selected card.
            .onScrollPhaseChange { oldPhase, newPhase in
                guard oldPhase == .animating, newPhase == .idle, let selectedExerciseIndex else { return }
                proxy.scrollTo(selectedExerciseIndex, anchor: .center)
            }
            .onChange(of: selectedExerciseIndex) { _, newValue in
                guard let newValue else { return }

                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: 75)
    }

    /// Changes when the strip is laid out or resized, but not when it is scrolled.
    private static func layoutKey(_ geometry: ScrollGeometry) -> [CGFloat] {
        [geometry.contentSize.width, geometry.containerSize.width, geometry.contentInsets.leading]
    }

    /// Selected is solid blue, done exercises are tinted blue, the rest stay plain.
    private func card(_ title: String, index: Int, isDone: Bool, width: CGFloat) -> some View {
        let isSelected = selectedExerciseIndex == index

        return Button {
            selectExercise(at: index)
        } label: {
            Text(title)
                .font(isSelected ? .default : .caption2)
                .fontWeight(isSelected ? .medium : .thin)
                .foregroundStyle(isSelected ? Color.white : isDone ? Color.accentColor : Color.primary)
                .frame(width: width, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: LayoutMetrics.compactCornerRadius)
                        .fill(
                            isSelected
                                ? Color.accentColor
                                : isDone
                                    ? Color.accentColor.opacity(VisualOpacity.light)
                                    : Color.gray.opacity(VisualOpacity.subtle)
                        )
                )
        }
        .accessibilityValue(isDone ? "Done" : "")
        .accessibilityHint(workoutExercises.indices.contains(index) && !workoutExercises[index].supersetPartners.isEmpty ? "Superset" : "")
        .id(index)
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
            selectedExerciseIndex = index
        }
    }
}
