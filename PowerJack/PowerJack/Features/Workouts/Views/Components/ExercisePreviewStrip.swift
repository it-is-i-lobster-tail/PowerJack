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
                        Button {
                            selectExercise(at: index)
                        } label: {
                            Text(workoutExercises[index].exercise.exerciseName)
                                .font(selectedExerciseIndex == index ? .default : .caption2)
                                .fontWeight(selectedExerciseIndex == index ? .medium : .thin)
                                .foregroundStyle(selectedExerciseIndex == index ? .white : .primary)
                                .frame(width: cardWidth, height: 54)
                                .background(
                                    RoundedRectangle(cornerRadius: LayoutMetrics.compactCornerRadius)
                                        .fill(
                                            selectedExerciseIndex == index
                                                ? Color.accentColor
                                                : Color.gray.opacity(VisualOpacity.subtle)
                                        )
                                )
                        }
                        .id(index)
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

    private func selectExercise(at index: Int) {
        withAnimation(.easeInOut(duration: 0.325)) {
            selectedExerciseIndex = index
        }
    }
}
