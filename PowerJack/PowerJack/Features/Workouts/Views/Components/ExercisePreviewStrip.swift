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

    @Binding var selectedExerciseIndex: Int?

    var body: some View {
        // Three whole cards fit on screen, so nothing is left half cut off.
        let spacing = LayoutMetrics.compactSpacing
        let cardWidth = max(0, (screenWidth - Self.edgeMargin * 2 - spacing * (Self.visibleCards - 1)) / Self.visibleCards)

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: spacing) {
                    ForEach(workoutExercises.indices, id: \.self) { index in
                        card(
                            workoutExercises[index].exercise?.exerciseName ?? "",
                            index: index,
                            isDone: workoutExercises[index].isDone,
                            width: cardWidth
                        )
                    }

                    if showsReview {
                        card("Review", index: workoutExercises.count, isDone: false, width: cardWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Self.edgeMargin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .onAppear {
                // Center the restored exercise when a workout reopens mid-way.
                guard let selectedExerciseIndex else { return }
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
        .id(index)
    }

    private func selectExercise(at index: Int) {
        withAnimation(.easeInOut(duration: 0.325)) {
            selectedExerciseIndex = index
        }
    }
}
