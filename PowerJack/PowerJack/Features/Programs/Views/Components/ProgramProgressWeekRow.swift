//
//  ProgramProgressWeekRow.swift
//  PowerJack
//
//  Created by Codex on 7/14/26.
//

import SwiftUI

struct ProgramProgressWeekRow: View {
    let programWeek: ProgramWeek
    let columns: Int
    let rowWidth: CGFloat
    let cellHeight: CGFloat
    let dataCellWidth: CGFloat

    var body: some View {
        GridRow {
            Text("WK \(programWeek.order + 1)")
                .font(.caption)
                .frame(
                    width: rowWidth,
                    height: cellHeight
                )

            if programWeek.workouts.isEmpty {
                ForEach(1...columns, id: \.self) { _ in
                    ProgramProgressPlaceholderCell(
                        dataCellWidth: dataCellWidth,
                        cellHeight: cellHeight
                    )
                }
            } else {
                ForEach(programWeek.workouts, id: \.self) { workout in
                    let completedPercent: Double = workout.totalSets > 0
                        ? min(1, max(0, Double(workout.getCountCompletedSets()) / Double(workout.totalSets)))
                        : 0
                    let displayCompletedPercent: Int = Int((completedPercent * 100).rounded())

                    ProgramProgressCell(
                        completedPercent: completedPercent,
                        displayCompletedPercent: displayCompletedPercent,
                        dataCellWidth: dataCellWidth,
                        cellHeight: cellHeight
                    )
                }
            }
        }
    }
}

private struct ProgramProgressPlaceholderCell: View {
    let dataCellWidth: CGFloat
    let cellHeight: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LayoutMetrics.compactCornerRadius)
                .fill(.clear)
                .glassEffect(
                    .regular
                        .tint(.gray.opacity(VisualOpacity.subtle)),
                    in: .rect(cornerRadius: LayoutMetrics.compactCornerRadius)
                )

            Circle()
                .fill(.gray.opacity(VisualOpacity.subtle))
                .frame(
                    width: LayoutMetrics.compactSpacing,
                    height: LayoutMetrics.compactSpacing
                )
        }
        .frame(
            width: dataCellWidth,
            height: cellHeight
        )
    }
}

private struct ProgramProgressCell: View {
    let completedPercent: Double
    let displayCompletedPercent: Int
    let dataCellWidth: CGFloat
    let cellHeight: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LayoutMetrics.panelCornerRadius)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .green.opacity(VisualOpacity.light), location: 0),
                            .init(color: .green.opacity(VisualOpacity.light), location: completedPercent),
                            .init(color: .gray.opacity(VisualOpacity.light), location: completedPercent),
                            .init(color: .gray.opacity(VisualOpacity.light), location: 1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

            Text("\(displayCompletedPercent)%")
        }
        .frame(
            width: dataCellWidth,
            height: cellHeight
        )
        .powerJackGlassPanel()
    }
}
