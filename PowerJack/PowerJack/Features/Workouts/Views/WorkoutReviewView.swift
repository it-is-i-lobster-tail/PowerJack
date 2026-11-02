//
//  WorkoutReviewView.swift
//  PowerJack
//
//  The last page of a workout: the workout timer, every exercise with a check once it's done
//  and how long it and its sets took, and the button that finishes the workout.
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
                if workout.startedAt != nil {
                    WorkoutTimerSection(workout: workout)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

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
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 28)
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

/// Time since Start Workout, ticking each second.
private struct WorkoutTimerSection: View {
    let workout: Workout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            WorkoutTimeCard(
                title: "Workout timer",
                duration: workout.duration(at: context.date) ?? 0,
                caption: workout.startedAt.map { "Started \($0.formatted(date: .omitted, time: .shortened))" }
            )
        }
    }
}

private struct ReviewRow: View {
    let workoutExercise: WorkoutExercise

    private var setsLabel: String {
        let sets = workoutExercise.workingSets
        let label = "\(workoutExercise.completedWorkingSets) of \(sets.count) sets"
        guard let duration = workoutExercise.duration else { return label }
        return "\(label) · \(duration.elapsedText)"
    }

    /// Each logged set's time in order, e.g. "Sets 2:01 · 3:12", or `nil` before any is timed.
    private func setTimes(_ title: String, of sets: [WorkoutSet]) -> String? {
        let times = sets.compactMap(\.duration)
        guard !times.isEmpty else { return nil }
        return "\(title) " + times.map(\.elapsedText).joined(separator: " · ")
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
                    .monospacedDigit()

                ForEach(
                    [
                        setTimes("Warmups", of: workoutExercise.warmupSets),
                        setTimes("Sets", of: workoutExercise.workingSets),
                    ].compactMap { $0 },
                    id: \.self
                ) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
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
