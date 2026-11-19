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

    @Environment(IdleControls.self) private var idleControls: IdleControls?

    @State private var pageRequests = 0
    @State private var stripHeight: CGFloat = 0
    @State private var pageScroll = ExercisePageScroll()

    private static let stripFade = LayoutMetrics.compactSpacing * 2
    /// The fades under the top bar end this far above the bar's bottom edge, so they stay off the first line.
    static let topFadeLift = LayoutMetrics.compactSpacing * 2

    var body: some View {
        // The sets fill the screen and scroll under the bars, but come to rest between them.
        // The top inset ends just above the bar's bottom edge, so the fade under it stays clear of the first line.
        WorkoutExercisePager(
            screenWidth: screenWidth,
            workoutExercises: workoutExercises,
            onExerciseSetsDone: onExerciseSetsDone,
            selectedExerciseIndex: $selectedExerciseIndex,
            focusedSetField: focusedSetField,
            review: review,
            pageRequests: pageRequests,
            pageScroll: pageScroll,
            pageInsets: EdgeInsets(top: topInset - Self.topFadeLift, leading: 0, bottom: stripHeight, trailing: 0)
        )
        .overlay(alignment: .top) {
            EdgeBlur(edge: .top)
                .frame(height: topInset - Self.topFadeLift)
        }
        .overlay(alignment: .bottom) {
            ExercisePreviewStrip(
                workoutExercises: workoutExercises,
                screenWidth: screenWidth,
                showsReview: review != nil,
                pageScroll: pageScroll,
                selectedExerciseIndex: $selectedExerciseIndex,
                onReselect: { pageRequests += 1 }
            )
            // The sets fade out in the gap above the strip, so none show between its cards.
            .padding(.top, Self.stripFade)
            .background { EdgeBlur(edge: .bottom, fadeLength: Self.stripFade) }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
            .fadesWhenIdle(idleControls)
        }
        .frame(width: screenWidth)
    }
}
