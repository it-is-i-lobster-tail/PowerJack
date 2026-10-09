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
    let onSelectWorkout: (Workout) -> Void

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
                    let progress = workout.setProgress
                    let cell = ProgramProgressCell(
                        completedFraction: progress.completed,
                        skippedFraction: progress.skipped,
                        dataCellWidth: dataCellWidth,
                        cellHeight: cellHeight
                    )

                    // Only the workout underway or one already completed has anything to show.
                    if workout.status == .active || workout.status == .complete {
                        Button { onSelectWorkout(workout) } label: { cell }
                            .buttonStyle(.plain)
                            .accessibilityHint(workout.status == .active ? "Resumes the workout" : "Shows the workout")
                    } else {
                        cell
                    }
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
    let completedFraction: Double
    let skippedFraction: Double
    let dataCellWidth: CGFloat
    let cellHeight: CGFloat

    // Completed fills from the bottom in blue, skipped stacks on top in grey, and the rest stays empty.
    private var completedTop: Double { min(1, max(0, completedFraction)) }
    private var resolvedTop: Double { min(1, max(completedTop, completedFraction + skippedFraction)) }
    private var displayPercent: Int { Int((resolvedTop * 100).rounded()) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LayoutMetrics.panelCornerRadius)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .blue.opacity(VisualOpacity.light), location: 0),
                            .init(color: .blue.opacity(VisualOpacity.light), location: completedTop),
                            .init(color: .gray.opacity(VisualOpacity.light), location: completedTop),
                            .init(color: .gray.opacity(VisualOpacity.light), location: resolvedTop),
                            .init(color: .clear, location: resolvedTop),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

            Text("\(displayPercent)%")
        }
        .frame(
            width: dataCellWidth,
            height: cellHeight
        )
        .powerJackGlassPanel()
    }
}
