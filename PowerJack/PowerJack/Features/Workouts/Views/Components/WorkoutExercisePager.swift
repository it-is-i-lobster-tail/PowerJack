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
    /// Reports how far the pages have scrolled, so the exercise strip can follow the swipe.
    var pageScroll: ExercisePageScroll? = nil
    /// Room for the bars over the pages. Each page scrolls under them but comes to rest inside.
    var pageInsets = EdgeInsets()

    @State private var scrollPhase: ScrollPhase = .idle

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
                            .safeAreaPadding(pageInsets)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }

                    if let review {
                        review
                            // The List keeps scrolling and its swipe actions while the pager is held still.
                            .environment(\.isScrollEnabled, true)
                            .safeAreaPadding(pageInsets)
                            .containerRelativeFrame(.horizontal)
                            .id(workoutExercises.count)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $selectedExerciseIndex)
            // Paging would swallow the Review rows' swipe actions; the exercise strip still leaves Review.
            .scrollDisabled(isOnReview)
            // Quick strip taps can cut a page scroll short. Once it stops, land on the selected page.
            .onScrollPhaseChange { oldPhase, newPhase in
                scrollPhase = newPhase
                guard oldPhase == .animating, newPhase == .idle else { return }
                showSelectedPage(proxy)
            }
            // A workout resumed mid-way sets its page before the pages are laid out, and the scroll
            // position alone can lose it. Land on it on appear and again once the layout settles,
            // as the exercise strip does, but never while the lifter is swiping.
            .onAppear { showSelectedPage(proxy) }
            .onScrollGeometryChange(for: CGFloat.self, of: Self.pagePosition) { _, position in
                pageScroll?.position = position
            }
            .onScrollGeometryChange(for: [CGFloat].self, of: Self.layoutKey) { _, _ in
                guard scrollPhase == .idle else { return }
                showSelectedPage(proxy)
            }
            .onChange(of: pageRequests) {
                withAnimation(.easeInOut(duration: 0.325)) { showSelectedPage(proxy) }
            }
        }
        // A superset change moves exercises between pages. The pages are keyed by position, so the pager
        // starts fresh on the selected page instead of keeping its old scroll state and each page's state.
        .id(workoutExercises.map(\.persistentModelID))
    }

    private func showSelectedPage(_ proxy: ScrollViewProxy) {
        guard let selectedExerciseIndex else { return }
        proxy.scrollTo(selectedExerciseIndex)
    }

    /// Changes when the pages are laid out or resized, but not when they're scrolled.
    private static func layoutKey(_ geometry: ScrollGeometry) -> [CGFloat] {
        [geometry.contentSize.width, geometry.containerSize.width]
    }

    /// How many pages in from the first page the pages have scrolled, part pages included.
    private static func pagePosition(_ geometry: ScrollGeometry) -> CGFloat {
        guard geometry.containerSize.width > 0 else { return 0 }
        return (geometry.contentOffset.x + geometry.contentInsets.leading) / geometry.containerSize.width
    }

    private var isOnReview: Bool {
        review != nil && selectedExerciseIndex == workoutExercises.count
    }
}
