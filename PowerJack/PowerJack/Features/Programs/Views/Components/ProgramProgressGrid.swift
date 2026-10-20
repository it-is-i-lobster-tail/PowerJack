//
//  ProgramProgressGrid.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
//

import SwiftUI

/// The whole program at a glance, laid out like a calendar: weeks down, days across.
struct ProgramProgressGrid: View {
    let program: Program

    @Environment(ProgramsRouter.self) private var router

    var body: some View {
        let days = max(1, program.workoutsPerWeek)
        let nextWorkout = program.nextWorkout

        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Text("Progress")
                .font(.headline)

            Grid(horizontalSpacing: LayoutMetrics.compactSpacing, verticalSpacing: 6) {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(1...days, id: \.self) { day in
                        Text("Day \(day)")
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(program.programWeeks) { programWeek in
                    let week = programWeek.order + 1
                    // Later weeks have no workouts until the program gets there, so they show as planned.
                    let workouts = programWeek.workouts

                    GridRow {
                        Text("W\(week)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)

                        ForEach(0..<days, id: \.self) { index in
                            let workout = workouts.indices.contains(index) ? workouts[index] : nil
                            cell(
                                for: workout,
                                isNext: workout != nil && workout === nextWorkout,
                                label: "Week \(week), Day \(index + 1)"
                            )
                        }
                    }
                }
            }
        }
        .padding(LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .powerJackGlassPanel()
    }

    /// Only the workout underway or one already completed has anything to show.
    @ViewBuilder
    private func cell(for workout: Workout?, isNext: Bool, label: String) -> some View {
        let dot = ProgramProgressDot(status: workout?.status ?? .planned, isNext: isNext)

        if let workout, workout.status == .active || workout.status == .complete {
            Button { router.showWorkout(workout, in: program) } label: { dot }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label), \(dot.statusDescription)")
                .accessibilityHint(workout.status == .active ? "Resumes the workout" : "Shows the workout")
        } else {
            dot
                .accessibilityElement()
                .accessibilityLabel("\(label), \(dot.statusDescription)")
        }
    }
}

/// One workout: blue when done, green while underway, a dash when skipped, and an outline until then.
/// The next workout is drawn larger so it's easy to see where the program is.
private struct ProgramProgressDot: View {
    let status: Status
    let isNext: Bool

    private static let size: CGFloat = 20
    private static let nextSize: CGFloat = 30

    var statusDescription: String {
        switch status {
        case .complete: "done"
        case .active: "in progress"
        case .skipped: "skipped"
        default: isNext ? "up next" : "planned"
        }
    }

    var body: some View {
        ZStack {
            switch status {
            case .complete:
                Circle().fill(.blue)
            case .active:
                Circle().fill(.green)
            case .skipped:
                Circle().fill(.gray.opacity(VisualOpacity.light))
                Image(systemName: "minus")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            default:
                Circle().strokeBorder(
                    isNext ? Color.blue : Color.gray.opacity(VisualOpacity.standard),
                    lineWidth: isNext ? 3 : 1.5
                )
            }
        }
        .frame(width: isNext ? Self.nextSize : Self.size, height: isNext ? Self.nextSize : Self.size)
        .frame(maxWidth: .infinity, minHeight: Self.nextSize)
        .contentShape(.rect)
    }
}
