//
//  SubstitutePicker.swift
//  PowerJack
//
//  Picks a one-time substitute: exercises for the same primary muscle as the planned one.
//

import SwiftData
import SwiftUI

struct SubstitutePicker: View {
    let workoutExercise: WorkoutExercise
    let onSelect: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [Exercise]

    private var options: [Exercise] { workoutExercise.substituteOptions(from: exercises) }

    var body: some View {
        NavigationStack {
            Group {
                if options.isEmpty {
                    EmptyStateView(title: "No substitutes", systemImage: "arrow.triangle.swap")
                } else {
                    List(options) { exercise in
                        Button {
                            onSelect(exercise)
                            dismiss()
                        } label: {
                            row(exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Substitute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
        .traceScreen("Substitute Picker")
    }

    private func row(_ exercise: Exercise) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(exercise.exerciseName)
                    .foregroundStyle(.primary)
                Text(exercise.equipment.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if exercise === workoutExercise.substitute {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)
    }
}

#Preview("SubstitutePicker") {
    let scenario = PowerJackSeed.weekOneProgress()

    SubstitutePicker(workoutExercise: scenario.weekOneWorkouts[2].workoutExercises[0], onSelect: { _ in })
        .modelContainer(scenario.container)
}
