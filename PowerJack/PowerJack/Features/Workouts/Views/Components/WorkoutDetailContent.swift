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

    @State private var pageRequests = 0
    @State private var stripHeight: CGFloat = 0

    private static let stripFade = LayoutMetrics.compactSpacing * 2

    var body: some View {
        // The sets fill the screen and scroll under the bars, but come to rest between them.
        WorkoutExercisePager(
            screenWidth: screenWidth,
            workoutExercises: workoutExercises,
            onExerciseSetsDone: onExerciseSetsDone,
            selectedExerciseIndex: $selectedExerciseIndex,
            focusedSetField: focusedSetField,
            review: review,
            pageRequests: pageRequests,
            pageInsets: EdgeInsets(top: topInset + LayoutMetrics.compactSpacing, leading: 0, bottom: stripHeight, trailing: 0)
        )
        .overlay(alignment: .top) {
            EdgeBlur(edge: .top)
                .frame(height: topInset)
        }
        .overlay(alignment: .bottom) {
            ExercisePreviewStrip(
                workoutExercises: workoutExercises,
                screenWidth: screenWidth,
                showsReview: review != nil,
                selectedExerciseIndex: $selectedExerciseIndex,
                onReselect: { pageRequests += 1 }
            )
            // The sets fade out in the gap above the strip, so none show between its cards.
            .padding(.top, Self.stripFade)
            .background { EdgeBlur(edge: .bottom, fadeLength: Self.stripFade) }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
        }
        .frame(width: screenWidth)
    }
}
