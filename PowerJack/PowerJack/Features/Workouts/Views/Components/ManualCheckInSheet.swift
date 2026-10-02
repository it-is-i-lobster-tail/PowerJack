//
//  ManualCheckInSheet.swift
//  PowerJack
//
//  Asks how to continue an exercise that caused severe pain last week.
//

import SwiftData
import SwiftUI

struct ManualCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var workoutExercise: WorkoutExercise
    let onResolved: () -> Void

    private var painLabel: String {
        workoutExercise.checkInSourcePain?.label.lowercased() ?? "high"
    }

    var body: some View {
        GlassEffectContainer(spacing: LayoutMetrics.sectionSpacing) {
            VStack(spacing: LayoutMetrics.sectionSpacing) {
                VStack(spacing: 4) {
                    Image(systemName: "cross.case")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Check In")
                        .font(.title)
                    Text("Last time \(workoutExercise.exercise.exerciseName) caused \(painLabel) pain. How do you want to continue?")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 10)

                ForEach(ManualCheckInDecision.allCases) { decision in
                    Button {
                        resolve(decision)
                    } label: {
                        CheckInOption(decision: decision)
                    }
                    .buttonStyle(.plain)
                    .powerJackGlassCard(interactive: true)
                }
            }
            .padding(.vertical, 10)
            .powerJackGlassPanel()
        }
    }

    private func resolve(_ decision: ManualCheckInDecision) {
        workoutExercise.resolveCheckIn(decision)
        dismiss()
        onResolved()
    }
}

private struct CheckInOption: View {
    let decision: ManualCheckInDecision

    private var title: String {
        switch decision {
        case .continue: "Continue"
        case .reset: "Reset"
        case .skip: "Skip Exercise"
        }
    }

    private var detail: String {
        switch decision {
        case .continue: "Log the same sets, reps, and weight as last time."
        case .reset: "Start over with two fresh sets."
        case .skip: "Skip this exercise today. You'll be asked again next week."
        }
    }

    private var systemImage: String {
        switch decision {
        case .continue: "arrow.right.circle"
        case .reset: "arrow.counterclockwise.circle"
        case .skip: "forward.circle"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .frame(maxWidth: .infinity, minHeight: 60)
        .contentShape(.rect)
    }
}

#Preview("ManualCheckInSheet") {
    let scenario = PowerJackSeed.weekTwoProgression()

    ManualCheckInSheet(
        workoutExercise: scenario.checkInExercise,
        onResolved: {}
    )
    .padding(.horizontal, LayoutMetrics.sectionSpacing)
    .modelContainer(scenario.container)
}
