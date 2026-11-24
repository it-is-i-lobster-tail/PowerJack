//
//  WatchFinishView.swift
//  PowerJackWatch
//

import SwiftUI

/// The overview opened from an exercise and automatically after the last exercise.
struct WatchFinishView: View {
    @Environment(\.dismiss) private var dismiss

    let workout: Workout
    let selectedExercise: WorkoutExercise?
    let onSelectExercise: (Int) -> Void
    let onSkipWarmups: (WorkoutExercise) -> Void
    let onFinish: () -> Void

    @State private var isConfirmingFinish = false
    @State private var isConfirmingWarmups = false

    private var remainingSets: Int { workout.remainingWorkingSets }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(workout.workoutExercises.enumerated()), id: \.element.id) { index, exercise in
                    Button {
                        onSelectExercise(index)
                    } label: {
                        WatchExerciseProgressRow(exercise: exercise)
                    }
                }

                if let selectedExercise, selectedExercise.nextSet?.isWarmup == true, !selectedExercise.checkInPending {
                    Button("Skip Remaining Warmups", systemImage: "forward.end") {
                        isConfirmingWarmups = true
                    }
                    .confirmationDialog(
                        "Skip remaining warmups for \(selectedExercise.shownExercise?.exerciseName ?? "this exercise")?",
                        isPresented: $isConfirmingWarmups,
                        titleVisibility: .visible
                    ) {
                        Button("Skip Warmups", role: .destructive) { onSkipWarmups(selectedExercise) }
                    }
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                Button {
                    if remainingSets > 0 {
                        isConfirmingFinish = true
                    } else {
                        onFinish()
                    }
                } label: {
                    Text("Finish Workout").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
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
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

struct WatchExerciseProgressRow: View {
    let exercise: WorkoutExercise

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(exercise.shownExercise?.exerciseName ?? "")
                    .fixedSize(horizontal: false, vertical: true)
                Text(exercise.workingSetsDoneText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if exercise.status == .skipped {
                Image(systemName: "forward.end")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Skipped")
            } else if exercise.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Done")
            }
        }
    }
}
