//
//  WorkoutDetailContent.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct WorkoutDetailContent: View {
    let screenWidth: CGFloat
    /// How far down the navigation bar reaches. The sets scroll up under it.
    let topInset: CGFloat
    let workoutExercises: [WorkoutExercise]
    @Binding var selectedExerciseIndex: Int?
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    let onExerciseSetsDone: (WorkoutExercise) -> Void
    var review: WorkoutReviewView? = nil
    /// Where the pages are, shared with the strip and the header.
    let pageScroll: ExercisePageScroll

    @Environment(IdleControls.self) private var idleControls: IdleControls?

    @State private var pageRequests = 0

    var body: some View {
        let hidden = idleControls?.isHidden == true
        let revealing = hidden && pageScroll.swipeStartPage != nil
        let offset = pageScroll.swipeOffset(lastPage: review == nil ? workoutExercises.count - 1 : workoutExercises.count)
        WorkoutExercisePager(
            screenWidth: screenWidth,
            workoutExercises: workoutExercises,
            onExerciseSetsDone: onExerciseSetsDone,
            selectedExerciseIndex: $selectedExerciseIndex,
            focusedSetField: focusedSetField,
            review: review,
            pageRequests: pageRequests,
            pageScroll: pageScroll,
            topInset: topInset,
            controlsHidden: hidden
        )
        .overlay(alignment: .top) {
            EdgeBlur(edge: .top)
                .frame(height: topInset)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ExercisePreviewStrip(
                workoutExercises: workoutExercises,
                screenWidth: screenWidth,
                showsReview: review != nil,
                pageScroll: pageScroll,
                selectedExerciseIndex: $selectedExerciseIndex,
                onReselect: { pageRequests += 1 }
            )
            .padding(.top, LayoutMetrics.compactSpacing)
            // Bring the cards up from the bottom along the incoming page’s edge.
            .offset(y: revealing ? 8 * (1 - abs(offset)) : 0)
            // Reveal only the portion over the incoming page, following its edge in either direction.
            .mask {
                Rectangle().scaleEffect(x: revealing ? abs(offset) : 1, y: 1,
                                        anchor: offset < 0 ? .leading : .trailing)
            }
            .opacity(hidden && !revealing ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
            .frame(height: idleControls?.previewStripCollapsed == true && !revealing ? 0 : nil)
        }
        .frame(width: screenWidth)
    }
}
