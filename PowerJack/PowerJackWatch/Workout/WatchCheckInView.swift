//
//  WatchCheckInView.swift
//  PowerJackWatch
//
//  Asks how to continue an exercise that caused severe pain last time, as the iPhone does.
//

import SwiftData
import SwiftUI

struct WatchCheckInView: View {
    @Bindable var workoutExercise: WorkoutExercise
    let onResolved: () -> Void

    /// Strengthen has already planned lighter sets, so Continue logs those and there is no Reset.
    private var offersLighter: Bool { workoutExercise.strengthRole != nil }

    private var decisions: [ManualCheckInDecision] {
        offersLighter ? [.continue, .skip] : ManualCheckInDecision.allCases
    }

    private var painLabel: String {
        workoutExercise.checkInSourcePain?.label.lowercased() ?? "high"
    }

    var body: some View {
        List {
            Section {
                ForEach(decisions) { decision in
                    Button {
                        workoutExercise.resolveCheckIn(decision)
                        onResolved()
                    } label: {
                        Label(title(for: decision), systemImage: systemImage(for: decision))
                    }
                }
            } header: {
                Text("Last time \(workoutExercise.exercise?.exerciseName ?? "this") caused \(painLabel) pain.")
                    .textCase(nil)
            }
        }
        .interactiveDismissDisabled()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func title(for decision: ManualCheckInDecision) -> String {
        switch decision {
        case .continue: offersLighter ? "Go Lighter" : "Same as Last Time"
        case .reset: "Start Over"
        case .skip: "Skip Today"
        }
    }

    private func systemImage(for decision: ManualCheckInDecision) -> String {
        switch decision {
        case .continue: offersLighter ? "arrow.down.circle" : "arrow.right.circle"
        case .reset: "arrow.counterclockwise.circle"
        case .skip: "forward.circle"
        }
    }
}
