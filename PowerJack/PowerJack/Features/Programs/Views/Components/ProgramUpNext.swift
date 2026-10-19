//
//  ProgramUpNext.swift
//  PowerJack
//
//  The workout the lifter does next: where it sits in the program, its exercises, and Start or Resume.
//

import SwiftUI

struct ProgramUpNext: View {
    let program: Program
    let workout: Workout
    let startHint: (any Hint)?

    private var isInProgress: Bool { workout.status == .active }

    private var title: String {
        let day = workout.order + 1
        guard let week = program.weekNumber(containing: workout) else { return "Day \(day)" }
        return "Week \(week) · Day \(day)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Text(isInProgress ? "In progress" : "Up next")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isInProgress ? .green : .secondary)

            Text(title)
                .font(.title2.bold())

            VStack(spacing: 6) {
                ForEach(workout.workoutExercises) { workoutExercise in
                    HStack {
                        Text(workoutExercise.exercise?.exerciseName ?? "Exercise")
                        Spacer()
                        Text(setCount(workoutExercise.workingSets.count))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
            .padding(.vertical, LayoutMetrics.compactSpacing)

            ProgramStartWorkout(program: program, workout: workout)
                .popoverHint(startHint)
        }
        .padding(LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .powerJackGlassPanel()
    }

    private func setCount(_ count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }
}
