//
//  SupersetPicker.swift
//  PowerJack
//

import SwiftData
import SwiftUI

/// Picks what an exercise joins: another exercise on its own, or a whole superset.
/// The exercise it was opened from stays first, and the pick moves to follow it.
struct SupersetPicker: View {
    @Environment(\.dismiss) private var dismiss

    let workout: Workout
    let workoutExercise: WorkoutExercise
    let onPick: ([WorkoutExercise]) -> Void

    private var choices: [[WorkoutExercise]] {
        workout.supersetChoices(for: workoutExercise)
    }

    var body: some View {
        // Its own stack is safe here: a sheet is a new presentation, not a push on the Programs stack.
        NavigationStack {
            List {
                Section {
                    // Keyed by exercise, not position: a pick shrinks the list while the sheet is still closing.
                    ForEach(choices, id: \.first?.persistentModelID) { choice in
                        Button {
                            onPick(choice)
                            dismiss()
                        } label: {
                            row(for: choice)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 20))
                    }
                } header: {
                    // Above the list, so it shows at half height.
                    if let name = workoutExercise.exercise?.exerciseName {
                        Text("\(name.localizedCapitalized) stays first. What you pick moves to follow it.")
                            .textCase(nil)
                    }
                }
            }
            .navigationTitle("Add to Superset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    @ViewBuilder
    private func row(for choice: [WorkoutExercise]) -> some View {
        if choice.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                Label("Superset \(workout.supersetLetter(for: choice))", systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                    // Start the row's divider in line with the exercise names, not under the label text after the icon.
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    .padding(.horizontal, 15)
                    .padding(.top, 8)
                ForEach(choice) { member in
                    if let exercise = member.exercise {
                        SupersetExerciseLabel(exercise: exercise)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else if let exercise = choice.first?.exercise {
            SupersetExerciseLabel(exercise: exercise)
        }
    }
}
