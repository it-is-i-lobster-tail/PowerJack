//
//  WatchFinishView.swift
//  PowerJackWatch
//
//  The last page: every exercise with a check once it's done, and Finish Workout.
//

import SwiftData
import SwiftUI

struct WatchFinishView: View {
    let workout: Workout
    let onSelectExercise: (Int) -> Void
    let onFinish: () -> Void

    @State private var isConfirmingFinish = false

    private var remainingSets: Int { workout.remainingWorkingSets }

    var body: some View {
        List {
            ForEach(Array(workout.workoutExercises.enumerated()), id: \.element.id) { index, workoutExercise in
                Button {
                    onSelectExercise(index)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(workoutExercise.exercise?.exerciseName ?? "")
                                .lineLimit(1)
                            Text("\(workoutExercise.completedWorkingSets) of \(workoutExercise.workingSets.count) sets")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if workoutExercise.isDone {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("Done")
                        }
                    }
                }
            }

            Button("Finish Workout") {
                if remainingSets > 0 {
                    isConfirmingFinish = true
                } else {
                    onFinish()
                }
            }
            .buttonStyle(.borderedProminent)
            .listRowBackground(Color.clear)
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
}
