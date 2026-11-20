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
    @State private var stripHeight: CGFloat = 0

    var body: some View {
        // The first set rests below the pinned strip. Later sets can scroll under it.
        WorkoutExercisePager(
            screenWidth: screenWidth,
            workoutExercises: workoutExercises,
            onExerciseSetsDone: onExerciseSetsDone,
            selectedExerciseIndex: $selectedExerciseIndex,
            focusedSetField: focusedSetField,
            review: review,
            pageRequests: pageRequests,
            pageScroll: pageScroll,
            pageInsets: EdgeInsets(top: topInset + stripHeight, leading: 0, bottom: 0, trailing: 0)
        )
        .overlay(alignment: .top) {
            EdgeBlur(edge: .top)
                .frame(height: topInset)
        }
        .overlay(alignment: .top) {
            ExercisePreviewStrip(
                workoutExercises: workoutExercises,
                screenWidth: screenWidth,
                showsReview: review != nil,
                pageScroll: pageScroll,
                selectedExerciseIndex: $selectedExerciseIndex,
                onReselect: { pageRequests += 1 }
            )
            .padding(.top, LayoutMetrics.compactSpacing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
            .fadesWhenIdle(idleControls)
            .padding(.top, topInset)
        }
        .frame(width: screenWidth)
    }
}
