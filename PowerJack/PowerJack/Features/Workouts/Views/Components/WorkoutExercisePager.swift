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
    /// Goes up when the selected exercise is tapped again in the strip, to bring its page back.
    var pageRequests = 0
    let pageScroll: ExercisePageScroll
    /// Room for the bars over the pages. Each page scrolls under them but comes to rest inside.
    var pageInsets = EdgeInsets()

    @State private var scrollPhase: ScrollPhase = .idle
    @State private var pagerPosition = ScrollPosition()

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
                        .safeAreaPadding(pageInsets)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }

                if let review {
                    review
                        .safeAreaPadding(pageInsets)
                        .safeAreaPadding(.top, LayoutMetrics.compactSpacing)
                        .containerRelativeFrame(.horizontal)
                        .id(workoutExercises.count)
                }
            }
            .scrollTargetLayout(isEnabled: !pageScroll.isDrivenByStrip)
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition($pagerPosition)
        .onScrollPhaseChange { oldPhase, newPhase, context in
            scrollPhase = newPhase
            if newPhase == .tracking || newPhase == .interacting {
                pageScroll.isDrivenByStrip = false
            }
            guard !pageScroll.isDrivenByStrip, newPhase == .idle,
                  oldPhase == .interacting || oldPhase == .decelerating else { return }
            selectedExerciseIndex = Int(Self.pagePosition(context.geometry).rounded())
        }
        .onScrollGeometryChange(for: CGFloat.self, of: Self.pagePosition) { _, position in
            if !pageScroll.isDrivenByStrip { pageScroll.position = position }
        }
        .onChange(of: pageScroll.position) {
            if pageScroll.isDrivenByStrip {
                pagerPosition.scrollTo(x: pageScroll.position * screenWidth)
            }
        }
        .onChange(of: selectedExerciseIndex) { scrollToSelection(animated: true) }
        .onChange(of: pageRequests) { scrollToSelection(animated: true) }
        .onAppear { scrollToSelection(animated: false) }
        .onScrollGeometryChange(for: [CGFloat].self, of: Self.layoutKey) { _, _ in
            if scrollPhase == .idle && !pageScroll.stripPhase.isScrolling { scrollToSelection(animated: false) }
        }
        // A superset change moves exercises between pages. The pages are keyed by position, so the pager
        // starts fresh on the selected page instead of keeping its old scroll state and each page's state.
        .id(workoutExercises.map(\.persistentModelID))
    }

    private func scrollToSelection(animated: Bool) {
        guard let selectedExerciseIndex else { return }
        let target = CGFloat(selectedExerciseIndex)
        if animated && scrollPhase != .animating && abs(pageScroll.position - target) < 0.001 { return }
        pageScroll.isDrivenByStrip = false
        withAnimation(animated ? .easeInOut(duration: 0.325) : nil) {
            pagerPosition.scrollTo(x: target * screenWidth)
        }
    }

    /// Changes when the pages are laid out or resized, but not when they're scrolled.
    private nonisolated static func layoutKey(_ geometry: ScrollGeometry) -> [CGFloat] {
        [geometry.contentSize.width, geometry.containerSize.width]
    }

    /// How many pages in from the first page the pages have scrolled, part pages included.
    private nonisolated static func pagePosition(_ geometry: ScrollGeometry) -> CGFloat {
        guard geometry.containerSize.width > 0 else { return 0 }
        return (geometry.contentOffset.x + geometry.contentInsets.leading) / geometry.containerSize.width
    }
}
