//
//  WorkoutExercisePager.swift
//  PowerJack
//
//  Created by Brendon on 6/26/26.
//

import SwiftUI

struct WorkoutExercisePager: View {
    let screenWidth: CGFloat
    let workoutExercises: [WorkoutExercise]
    let onExerciseSetsDone: (WorkoutExercise) -> Void
    @Binding var selectedExerciseIndex: Int?
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    /// The Review page after the last exercise. Nil when the workout is read-only.
    var review: WorkoutReviewView? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(workoutExercises.indices, id: \.self) { index in
                    WorkoutExerciseView(
                        onSetsDone: onExerciseSetsDone,
                        screenWidth: screenWidth,
                        focusedSetField: focusedSetField,
                        workoutExercise: workoutExercises[index]
                    )
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }

                if let review {
                    review
                        // The List keeps scrolling and its swipe actions while the pager is held still.
                        .environment(\.isScrollEnabled, true)
                        .containerRelativeFrame(.horizontal)
                        .id(workoutExercises.count)
                }
            }
            .scrollTargetLayout()
            .padding(.top, LayoutMetrics.compactSpacing)
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $selectedExerciseIndex)
        // Paging would swallow the Review rows' swipe actions; the exercise strip still leaves Review.
        .scrollDisabled(isOnReview)
    }

    private var isOnReview: Bool {
        review != nil && selectedExerciseIndex == workoutExercises.count
    }
}
