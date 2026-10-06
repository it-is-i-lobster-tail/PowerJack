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
    }

    private func positiveFinite(_ value: CGFloat, fallback: CGFloat = 1) -> CGFloat {
        guard value.isFinite, value > 0 else { return fallback }
        return value
    }
}
