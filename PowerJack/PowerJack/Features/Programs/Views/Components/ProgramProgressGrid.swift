//
//  ProgramProgressGrid.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftUI

struct ProgramProgressGrid: View {
    let workableWidth: CGFloat
    let workableHeight: CGFloat
    let program: Program

    @Environment(ProgramsRouter.self) private var router
    @Namespace private var weekLabels
    /// Trails `currentWeek` so the pill can slide there each time the grid is shown.
    @State private var highlightedWeek: Int?

    /// The week of the workout to resume or start next. Nil unless the program is active.
    private var currentWeek: Int? {
        program.nextWorkout.flatMap { program.weekNumber(containing: $0) }
    }

    var body: some View {
        let layoutWidth = positiveFinite(workableWidth)
        let layoutHeight = positiveFinite(workableHeight)
        let rows = max(1, program.programLengthWeeks + 1) // header + weeks
        let columns = max(1, program.workoutsPerWeek)

        let gridHorizontalSpacing = LayoutMetrics.compactSpacing
        let gridVerticalSpacing = LayoutMetrics.compactSpacing
        let rowWidth: CGFloat = 33

        let totalVerticalSpacing = CGFloat(rows - 1) * gridVerticalSpacing
        let totalHorizontalSpacing = CGFloat(columns) * gridHorizontalSpacing

        let availableGridHeight = positiveFinite(layoutHeight - totalVerticalSpacing)
        let availableDataWidth = positiveFinite(layoutWidth - rowWidth - totalHorizontalSpacing)

        let cellHeight = availableGridHeight / CGFloat(rows)
        let columnCellHeight = cellHeight * 0.5
        let dataCellWidth = availableDataWidth / CGFloat(columns)

        GlassEffectContainer(spacing: gridHorizontalSpacing) {
            ZStack {
                if let highlightedWeek {
                    CurrentWeekPill()
                        .matchedGeometryEffect(id: highlightedWeek, in: weekLabels, isSource: false)
                }

                Grid(
                    horizontalSpacing: gridHorizontalSpacing,
                    verticalSpacing: gridVerticalSpacing
                ) {
                    // Column Headers
                    GridRow {
                        Text("")
                            .frame(
                                width: rowWidth,
                                height: columnCellHeight
                            )
                        ForEach(1...columns, id: \.self) { i in
                            Text("Day \(i)")
                                .frame(
                                    width: dataCellWidth,
                                    height: columnCellHeight
                                )
                        }
                    }

                    ForEach(program.programWeeks, id: \.self) { programWeek in
                        ProgramProgressWeekRow(
                            programWeek: programWeek,
                            columns: columns,
                            rowWidth: rowWidth,
                            cellHeight: cellHeight,
                            dataCellWidth: dataCellWidth,
                            weekLabels: weekLabels,
                            onSelectWorkout: { router.showWorkout($0, in: program) }
                        )
                    }
                }
                .frame(
                    width: layoutWidth,
                    height: layoutHeight
                )
                .padding(.leading, 4)
                .padding(.trailing, LayoutMetrics.compactSpacing)
            }
            .powerJackGlassPanel()
        }
        .onAppear { slideHighlight(to: currentWeek, animated: highlightedWeek != nil) }
        .onChange(of: currentWeek) { _, week in slideHighlight(to: week, animated: true) }
    }

    /// Builds speed slowly, then stops hard on the new week with no overshoot.
    private func slideHighlight(to week: Int?, animated: Bool) {
        guard week != highlightedWeek else { return }
        guard animated, week != nil else {
            highlightedWeek = week
            return
        }
        withAnimation(.timingCurve(0.7, 0, 0.9, 0.4, duration: 0.55)) {
            highlightedWeek = week
        }
    }

    private func positiveFinite(_ value: CGFloat, fallback: CGFloat = 1) -> CGFloat {
        guard value.isFinite, value > 0 else { return fallback }
        return value
    }
}

/// See-through green glass behind the current week's label.
private struct CurrentWeekPill: View {
    var body: some View {
        Color.clear
            .glassEffect(.clear.tint(.green.opacity(VisualOpacity.light)), in: .capsule)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
