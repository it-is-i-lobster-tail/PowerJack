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
    let pages: [WorkoutPage]
    let onExerciseSetsDone: (WorkoutExercise) -> Void
    @Binding var selectedPageIndex: Int?
    let selectedExerciseIndex: Int?
    let focusedSetField: FocusState<FocusedSetField?>.Binding
    /// The Review page after the last exercise. Nil when the workout is read-only.
    var review: WorkoutReviewView? = nil
    /// Goes up when the selected exercise is tapped again in the strip, to bring its page back.
    var pageRequests = 0
    let pageScroll: ExercisePageScroll
    let topInset: CGFloat
    @Environment(IdleControls.self) private var idleControls: IdleControls?

    @State private var scrollPhase: ScrollPhase = .idle
    @State private var pagerPosition = ScrollPosition()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(pages.indices, id: \.self) { index in
                    exercisePage(pages[index])
                        .safeAreaPadding(.top, topInset)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }

                if let review {
                    review
                        .safeAreaPadding(.top, topInset)
                        .safeAreaPadding(.top, LayoutMetrics.compactSpacing)
                        .containerRelativeFrame(.horizontal)
                        .id(pages.count)
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
                pageScroll.swipeStartPage = selectedPageIndex
            }
            defer {
                if newPhase == .idle || newPhase == .animating { pageScroll.swipeStartPage = nil }
            }
            guard !pageScroll.isDrivenByStrip, newPhase == .idle,
                  oldPhase == .interacting || oldPhase == .decelerating else { return }
            let destination = Int(Self.pagePosition(context.geometry).rounded())
            if destination != selectedPageIndex, idleControls?.isHidden == true { idleControls?.show() }
            selectedPageIndex = destination
        }
        .onScrollGeometryChange(for: CGFloat.self, of: Self.pagePosition) { _, position in
            if !pageScroll.isDrivenByStrip { pageScroll.position = position }
        }
        .onChange(of: pageScroll.position) {
            if pageScroll.isDrivenByStrip {
                pagerPosition.scrollTo(x: pageScroll.position * screenWidth)
            }
        }
        .onChange(of: selectedPageIndex) { scrollToSelection(animated: true) }
        .onChange(of: pageRequests) { scrollToSelection(animated: true) }
        .onAppear { scrollToSelection(animated: false) }
        .onScrollGeometryChange(for: [CGFloat].self, of: Self.layoutKey) { _, _ in
            if scrollPhase == .idle && !pageScroll.stripPhase.isScrolling { scrollToSelection(animated: false) }
        }
        // A superset change moves exercises between pages. The pages are keyed by position, so the pager
        // starts fresh on the selected page instead of keeping its old scroll state and each page's state.
        .id(pages.map { $0.exercises.map(\.persistentModelID) })
    }

    private func exercisePage(_ page: WorkoutPage) -> some View {
        let currentSet = page.letter == nil ? nil : page.exercises.first?.workoutValue?.currentSet?.workoutSet
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(zip(page.indices, page.exercises)), id: \.1.persistentModelID) { index, exercise in
                        WorkoutExerciseView(onSetsDone: onExerciseSetsDone, screenWidth: screenWidth,
                                            focusedSetField: focusedSetField, workoutExercise: exercise,
                                            memberLabel: page.letter.map { "\($0)\(index - page.startIndex + 1)" },
                                            currentSet: currentSet)
                            .id(exercise.persistentModelID)
                    }
                }
            }
            .keepsFocusAboveKeyboard(focusedSetField.wrappedValue?.setID)
            .onChange(of: selectedExerciseIndex, initial: true) { previous, selected in
                guard page.letter != nil, let selected, page.indices.contains(selected),
                      previous != selected || selected != page.startIndex else { return }
                let member = page.exercises[selected - page.startIndex]
                proxy.scrollTo(member.persistentModelID, anchor: .top)
            }
        }
    }

    private func scrollToSelection(animated: Bool) {
        guard let selectedPageIndex else { return }
        let target = CGFloat(selectedPageIndex)
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
