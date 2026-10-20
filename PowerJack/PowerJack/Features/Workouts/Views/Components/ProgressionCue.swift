//
//  ProgressionCue.swift
//  PowerJack
//
//  The planner's aim for the last set and why the plan changed, under an exercise's name.
//

import SwiftUI

struct ProgressionCue: View {
    let workoutExercise: WorkoutExercise

    var body: some View {
        if aim != nil || note != nil {
            VStack(spacing: 2) {
                if let aim {
                    Text(aim)
                        .font(.subheadline.weight(.semibold))
                }
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, LayoutMetrics.sectionSpacing)
            .padding(.top, LayoutMetrics.compactSpacing)
        }
    }

    private var aim: String? {
        guard let target = workoutExercise.rirTarget else { return nil }
        if workoutExercise.programWeek?.weekKind == .deload {
            return "Aim: at least \(target) reps left on every set"
        }
        if target == 0 {
            return "Last set: to failure (optional)"
        }
        return "Aim: \(target) \(target == 1 ? "rep" : "reps") left on your last set"
    }

    private var note: String? { workoutExercise.progressionNote }
}
