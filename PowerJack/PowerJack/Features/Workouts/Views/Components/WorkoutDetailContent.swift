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
    let pages: [WorkoutPage]
    @Binding var selectedExerciseIndex: Int?
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    let onExerciseSetsDone: (WorkoutExercise) -> Void
    var review: WorkoutReviewView? = nil
    /// Where the pages are, shared with the strip and the header.
    let pageScroll: ExercisePageScroll

    @Environment(IdleControls.self) private var idleControls: IdleControls?

    @State private var pageRequests = 0
    @State private var stripHeight: CGFloat = 0

    /// The filmstrip and pager count groups. Review links and set actions count individual exercises.
    private var selectedPage: Binding<Int?> {
        Binding {
            guard let selectedExerciseIndex else { return nil }
            return pages.firstIndex { $0.indices.contains(selectedExerciseIndex) } ?? pages.count
        } set: { index in
            guard let index else { return }
            if index == pages.count, review != nil {
                selectedExerciseIndex = pages.last?.indices.upperBound ?? 0
            } else if pages.indices.contains(index), !pages[index].indices.contains(selectedExerciseIndex ?? -1) {
                selectedExerciseIndex = pages[index].entryIndex
            }
        }
    }

    var body: some View {
        // The first set rests below the pinned strip. Later sets can scroll under it.
        WorkoutExercisePager(
            screenWidth: screenWidth,
            pages: pages,
            onExerciseSetsDone: onExerciseSetsDone,
            selectedPageIndex: selectedPage,
            selectedExerciseIndex: selectedExerciseIndex,
            focusedSetField: focusedSetField,
            review: review,
            pageRequests: pageRequests,
            pageScroll: pageScroll,
            pageInsets: EdgeInsets(top: topInset + (idleControls?.isHidden == true ? 0 : stripHeight), leading: 0, bottom: 0, trailing: 0)
        )
        .overlay(alignment: .top) {
            EdgeBlur(edge: .top)
                .frame(height: topInset)
        }
        .overlay(alignment: .top) {
            ExercisePreviewStrip(
                pages: pages,
                screenWidth: screenWidth,
                showsReview: review != nil,
                pageScroll: pageScroll,
                selectedPageIndex: selectedPage,
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
