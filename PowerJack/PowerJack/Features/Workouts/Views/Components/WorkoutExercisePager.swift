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
    let topInset: CGFloat
    let controlsHidden: Bool
    @Environment(IdleControls.self) private var idleControls: IdleControls?

    @State private var scrollPhase: ScrollPhase = .idle
    @State private var pagerPosition = ScrollPosition()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                // Pages keep their state with their exercise when one is added or removed.
                // They scroll by offset, so their order still sets where each one sits.
                ForEach(workoutExercises, id: \.persistentModelID) { workoutExercise in
                    WorkoutExerciseView(
                        onSetsDone: onExerciseSetsDone,
                        screenWidth: screenWidth,
                        focusedSetField: focusedSetField,
                        workoutExercise: workoutExercise
                    )
                        .safeAreaPadding(.top, topInset)
                        .containerRelativeFrame(.horizontal)
                }

                if let review {
                    review
                        .safeAreaPadding(.top, topInset + LayoutMetrics.compactSpacing)
                        .containerRelativeFrame(.horizontal)
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
            if newPhase == .interacting, pageScroll.swipeStartPage == nil {
                pageScroll.swipeStartPage = selectedExerciseIndex
            }
            defer {
                if newPhase == .idle || newPhase == .animating { pageScroll.swipeStartPage = nil }
            }
            guard !pageScroll.isDrivenByStrip, newPhase == .idle,
                  oldPhase == .interacting || oldPhase == .decelerating else { return }
            let destination = Int(Self.pagePosition(context.geometry).rounded())
            if destination != selectedExerciseIndex, controlsHidden { idleControls?.show() }
            selectedExerciseIndex = destination
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
        // Rebuild positional scroll targets when the exercise order changes.
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
