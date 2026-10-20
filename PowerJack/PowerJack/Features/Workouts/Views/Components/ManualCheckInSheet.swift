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

    /// Strengthen has already planned the lighter sets, so Continue logs those and there is no Reset (15.4).
    private var offersLighter: Bool {
        workoutExercise.strengthRole != nil
    }

    private var decisions: [ManualCheckInDecision] {
        offersLighter ? [.continue, .skip] : ManualCheckInDecision.allCases
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
                    Text("Last time \(workoutExercise.exercise?.exerciseName ?? "this exercise") caused \(painLabel) pain. How do you want to continue?")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 10)

                ForEach(decisions) { decision in
                    Button {
                        resolve(decision)
                    } label: {
                        CheckInOption(decision: decision, isLighter: offersLighter)
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
    let isLighter: Bool

    private var title: String {
        switch decision {
        case .continue: isLighter ? "Lighter" : "Continue"
        case .reset: "Reset"
        case .skip: "Skip Exercise"
        }
    }

    private var detail: String {
        switch decision {
        case .continue where isLighter: "Two sets, 20% lighter, with 3 or more reps left."
        case .continue: "Log the same sets, reps, and weight as last time."
        case .reset: "Start over with two fresh sets."
        case .skip where isLighter: "Skip this exercise today. You'll be asked again next time."
        case .skip: "Skip this exercise today. You'll be asked again next week."
        }
    }

    private var systemImage: String {
        switch decision {
        case .continue: isLighter ? "arrow.down.circle" : "arrow.right.circle"
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
