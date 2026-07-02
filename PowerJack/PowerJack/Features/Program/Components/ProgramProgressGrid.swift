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
    
    var body: some View {
        let girdHorizontalSpacing: CGFloat = 8
        let girdVerticalSpacing: CGFloat = 8
        let rowWidth: CGFloat = 33
        let dataWidthWorkable = workableWidth - rowWidth - (Double(program.templateProgram.workoutsPerWeek) * girdHorizontalSpacing)
        let dataCellWidth = (dataWidthWorkable / Double(program.templateProgram.workoutsPerWeek)) * 0.95
        let rowsTotal = program.programLengthWeeksValue + 1
        let cellHeight = (workableHeight - (Double(program.programLengthWeeks) * girdVerticalSpacing)) / Double(rowsTotal)
        let columnCellHeight = cellHeight * 0.5
        
        ZStack {

            Grid(horizontalSpacing: girdHorizontalSpacing, verticalSpacing: girdVerticalSpacing) {
                // Column Headers
                GridRow() {
                    Text("")
                        .frame(
                            width: rowWidth,
                            height: columnCellHeight
                        )
                    ForEach(1...program.templateProgram.workoutsPerWeek, id: \.self) {i in
                            Text("Day \(i)")
                            .frame(
                                width: dataCellWidth,
                                height: columnCellHeight
                            )
                    }
                }
                
                ForEach(0...program.programLengthWeeks - 1, id: \.self) {j in
                    GridRow {
                        Text("WK \(j + 1)")
                            .font(.caption)
                            .frame(
                                width: rowWidth,
                                height: cellHeight
                            )
                        let workouts: [Workout] = program.programWeeks[j].workouts
                        if workouts.isEmpty {
                            ForEach(1...program.templateProgram.workoutsPerWeek, id: \.self) {k in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.clear)
                                        .glassEffect(
                                            .regular
                                                .tint( .gray.opacity(OpacityPJ.focusHeavy)),
                                            in: .rect(cornerRadius: 8))
                                    
                                    Circle()
                                        .fill(.gray.opacity(OpacityPJ.focusHeavy))
                                        .frame(width: 10, height: 10)
                                }
                                .frame(
                                    width: dataCellWidth,
                                    height: cellHeight
                                )
                            }
                        } else {
                            ForEach(workouts, id: \.self) {workout in
                                
                                let completedPercent: Double = Double(workout.getCountCompletedSets()) / Double(workout.totalSets)
                                let displayCompletedPercent: Int = Int((completedPercent * 100).rounded())

                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(
                                            LinearGradient(
                                                stops: [
                                                    .init(color: .green, location: 0),
                                                    .init(color: .green, location: completedPercent),
                                                    .init(color: .gray, location: completedPercent),
                                                    .init(color: .gray, location: 1)
                                                ],
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                        )
                                        .glassEffect(
                                            .regular.tint(.white.opacity(OpacityPJ.focusLight)),
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
                width: workableWidth,
                height: workableHeight
            )
        }
        .glassEffect(
            .regular.tint(.white.opacity(OpacityPJ.focusLight)),
            in: .rect(cornerRadius: 14))
    }
}
