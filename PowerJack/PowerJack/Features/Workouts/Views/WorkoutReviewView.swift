//
//  WorkoutReviewView.swift
//  PowerJack
//
//  The last page of a workout: every exercise with a check once it's done,
//  and the button that finishes the workout.
//

import SwiftData
import SwiftUI

struct WorkoutReviewView: View {
    let workout: Workout
    let onSelectExercise: (Int) -> Void
    let onSkipRemainingSets: (WorkoutExercise) -> Void
    let onFinish: () -> Void

    @State private var isConfirmingFinish = false

    private var remainingSets: Int { workout.remainingWorkingSets }

    var body: some View {
        VStack(spacing: 0) {
            Text("Review")
                .font(.title)

            List {
                ForEach(Array(workout.workoutExercises.enumerated()), id: \.element.id) { index, workoutExercise in
                    Button {
                        onSelectExercise(index)
                    } label: {
                        ReviewRow(workoutExercise: workoutExercise)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        if !workoutExercise.allSetsDone() {
                            Button("Skip", systemImage: "forward") {
                                onSkipRemainingSets(workoutExercise)
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: finish) {
                Text("Finish Workout")
                    .font(.title3)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.glassProminent)
            .padding(.horizontal, LayoutMetrics.sectionSpacing)
            .padding(.bottom, LayoutMetrics.compactSpacing)
        }
        .confirmationDialog(
            "\(remainingSets) \(remainingSets == 1 ? "set isn't" : "sets aren't") logged",
            isPresented: $isConfirmingFinish,
            titleVisibility: .visible
        ) {
            Button("Skip and Finish", role: .destructive, action: onFinish)
        } message: {
            Text("Unlogged sets are skipped when the workout finishes.")
        }
    }

    /// Asks first when sets are still waiting, so nothing is skipped by accident.
    private func finish() {
        if remainingSets > 0 {
            isConfirmingFinish = true
        } else {
            onFinish()
        }
    }
}

private struct ReviewRow: View {
    let workoutExercise: WorkoutExercise

    private var setsLabel: String {
        let sets = workoutExercise.workingSets
        return "\(workoutExercise.completedWorkingSets) of \(sets.count) sets"
    }

    /// Green check when done, a grey skip mark when skipped, an empty circle while sets are waiting.
    private var status: (symbol: String, color: Color, label: String) {
        if workoutExercise.status == .skipped && workoutExercise.isDone {
            ("forward.circle.fill", .secondary, "Skipped")
        } else if workoutExercise.isDone {
            ("checkmark.circle.fill", .green, "Done")
        } else {
            ("circle", .secondary, "Not done")
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workoutExercise.exercise?.exerciseName ?? "")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(setsLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: status.symbol)
                .font(.title2)
                .foregroundStyle(status.color)
                .accessibilityLabel(status.label)
        }
        .contentShape(.rect)
    }
}

#Preview("WorkoutReviewView") {
    let scenario = PowerJackSeed.weekOneProgress()

    WorkoutReviewView(
        workout: scenario.weekOneWorkouts[2],
        onSelectExercise: { _ in },
        onSkipRemainingSets: { _ in },
        onFinish: {}
    )
    .modelContainer(scenario.container)
}
