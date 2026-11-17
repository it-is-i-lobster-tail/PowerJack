//
//  WorkoutSupersetEditor.swift
//  PowerJack
//

import SwiftData
import SwiftUI

/// A workout's superset in its own list: drag to change the order, swipe to take an exercise out,
/// or end the superset. Logged sets stay as they are.
struct WorkoutSupersetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let workout: Workout
    let supersetID: UUID

    private var superset: [WorkoutExercise]? {
        workout.superset(supersetID)
    }

    private var title: String {
        guard let superset else { return "Superset" }
        return "Superset \(workout.supersetLetter(for: superset))"
    }

    var body: some View {
        // Its own stack is safe here: a sheet is a new presentation, not a push on the Programs stack.
        NavigationStack {
            List {
                Section {
                    ForEach(superset ?? []) { workoutExercise in
                        HStack {
                            if let exercise = workoutExercise.exercise {
                                SupersetExerciseLabel(exercise: exercise)
                            }
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                workout.removeFromSuperset(workoutExercise)
                                save()
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .tint(.red)
                        }
                    }
                    .onMove { source, destination in
                        workout.moveExercises(inSuperset: supersetID, from: source, to: destination)
                        save()
                    }
                } footer: {
                    Text("Touch and hold to change the order. Swipe left to take an exercise out. It goes just before the superset.")
                }
            }
            .animation(.default, value: superset?.map(\.persistentModelID))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                Button(role: .destructive) {
                    workout.removeSuperset(supersetID)
                    save()
                } label: {
                    Text("Remove Superset")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.glass)
                .padding(.horizontal, LayoutMetrics.sectionSpacing)
                .padding(.bottom, LayoutMetrics.compactSpacing)
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        // Down to one exercise, or removed: the superset has ended, so there's nothing left to show.
        .onChange(of: superset == nil) { _, isGone in
            if isGone { dismiss() }
        }
    }

    private func save() {
        modelContext.saveTraced("superset edited")
    }
}

/// An exercise's name and equipment in plain text colors, so the superset sheets' rows don't read as links.
struct SupersetExerciseLabel: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading) {
            Text(exercise.exerciseName.localizedCapitalized)
            Text(exercise.equipment.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
    }
}
