//
//  ProgramProgressGrid.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftData
import SwiftUI

struct ProgramProgressGrid: View {
    let workableWidth: CGFloat
    let workableHeight: CGFloat
    let program: Program

    private func positiveFinite(_ value: CGFloat, fallback: CGFloat = 1) -> CGFloat {
        guard value.isFinite, value > 0 else { return fallback }
        return value
    }
    
    var body: some View {
        let layoutWidth = positiveFinite(workableWidth)
        let layoutHeight = positiveFinite(workableHeight)
        let rows = max(1, program.programLengthWeeks + 1) // header + weeks
        let columns = max(1, program.templateProgram.workoutsPerWeek)

        let gridHorizontalSpacing: CGFloat = 8
        let gridVerticalSpacing: CGFloat = 8
        let rowWidth: CGFloat = 33

        let totalVerticalSpacing = CGFloat(rows - 1) * gridVerticalSpacing
        let totalHorizontalSpacing = CGFloat(columns) * gridHorizontalSpacing

        let availableGridHeight = positiveFinite(layoutHeight - totalVerticalSpacing)
        let availableDataWidth = positiveFinite(layoutWidth - rowWidth - totalHorizontalSpacing)

        let cellHeight = availableGridHeight / CGFloat(rows)
        let columnCellHeight = cellHeight * 0.5
        let dataCellWidth = availableDataWidth / CGFloat(columns)
        
        ZStack {

            Grid(
                horizontalSpacing: gridHorizontalSpacing,
                verticalSpacing: gridVerticalSpacing
            ) {
                // Column Headers
                GridRow() {
                    Text("")
                        .frame(
                            width: rowWidth,
                            height: columnCellHeight
                            )
                    ForEach(1...columns, id: \.self) {i in
                            Text("Day \(i)")
                            .frame(
                                width: dataCellWidth,
                                height: columnCellHeight
                            )
                    }
                }
                
                ForEach(program.programWeeks, id: \.self) {programWeek in
                    GridRow {
                        Text("WK \(programWeek.order + 1)")
                            .font(.caption)
                            .frame(
                                width: rowWidth,
                                height: cellHeight
                            )
                        if programWeek.workouts.isEmpty {
                            ForEach(1...columns, id: \.self) {k in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.clear)
                                        .glassEffect(
                                            .regular
                                                .tint( .gray.opacity(OpacityPJ.focusThin)),
                                            in: .rect(cornerRadius: 8))
                                    
                                    Circle()
                                        .fill(.gray.opacity(OpacityPJ.focusThin))
                                        .frame(width: 8, height: 8)
                                }
                                .frame(
                                    width: dataCellWidth,
                                    height: cellHeight
                                )
                            }
                        } else {
                            ForEach(programWeek.workouts, id: \.self) {workout in
                                
                                let completedPercent: Double = workout.totalSets > 0
                                    ? min(1, max(0, Double(workout.getCountCompletedSets()) / Double(workout.totalSets)))
                                    : 0
                                let displayCompletedPercent: Int = Int((completedPercent * 100).rounded())

                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(
                                            LinearGradient(
                                                stops: [
                                                    .init(color: .green.opacity(OpacityPJ.focusLight), location: 0),
                                                    .init(color: .green.opacity(OpacityPJ.focusLight), location: completedPercent),
                                                    .init(color: .gray.opacity(OpacityPJ.focusLight), location: completedPercent),
                                                    .init(color: .gray.opacity(OpacityPJ.focusLight), location: 1)
                                                ],
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                        )
                                        .glassEffect(
                                            .regular.tint(.white.opacity(OpacityPJ.focusThin)),
                                            in: .rect(cornerRadius: 14)
                                        )
                                    
                                    Text("\(displayCompletedPercent)%")
                                }
                                .frame(
                                    width: dataCellWidth,
                                    height: cellHeight
                                )
                            }
                        }
                    }
                }
            }
            .frame(
                width: layoutWidth,
                height: layoutHeight
            )
            .padding(.leading, 4)
            .padding(.trailing, 8)
        }
        .glassEffect(
            .regular.tint(.white.opacity(OpacityPJ.focusThin)),
            in: .rect(cornerRadius: 14))
    }
}
