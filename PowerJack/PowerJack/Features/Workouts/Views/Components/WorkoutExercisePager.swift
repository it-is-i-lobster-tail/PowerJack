//
//  WorkoutExercisePager.swift
//  PowerJack
//
//  Created on 6/26/26.
//

import SwiftData
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
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(workoutExercises.indices, id: \.self) { index in
                        WorkoutExerciseView(
                            onSetsDone: onExerciseSetsDone,
                            screenWidth: screenWidth,
                            focusedSetField: focusedSetField,
                            workoutExercise: workoutExercises[index]
                        )
                            // A superset change moves exercises between pages. Each page starts fresh
                            // for its new exercise instead of keeping the last one's state.
                            .id(workoutExercises[index].persistentModelID)
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
            // Quick strip taps can cut a page scroll short. Once it stops, land on the selected page.
            .onScrollPhaseChange { oldPhase, newPhase in
                guard oldPhase == .animating, newPhase == .idle, let selectedExerciseIndex else { return }
                proxy.scrollTo(selectedExerciseIndex)
            }
        }
    }

    private var isOnReview: Bool {
        review != nil && selectedExerciseIndex == workoutExercises.count
    }
}
