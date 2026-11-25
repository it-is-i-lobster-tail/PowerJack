import SwiftUI

struct WatchExerciseMenu: View {
    @Environment(\.dismiss) private var dismiss

    let exercise: WorkoutExercise
    let workout: Workout
    let apply: (WatchChange.ExerciseEdit, WorkoutExercise) -> Void
    let onSkipWorkout: () -> Void

    @State private var confirmsSkip = false

    @State private var confirmsSkipWorkout = false

    private var setType: SetType? { exercise.nextSet?.setType }

    var body: some View {
        NavigationStack {
            List {
                if let setType, !exercise.locked {
                    if exercise.canAddSet(type: setType) {
                        Button("Add Set", systemImage: "plus") {
                            apply(.addSet(setType, id: UUID()), exercise)
                            dismiss()
                        }
                    }
                    let sets = exercise.sets(ofType: setType)
                    if sets.count > 1, exercise.canRemoveSet(type: setType), let id = sets.last?.syncID {
                        Button("Remove Set", systemImage: "minus") {
                            apply(.removeSet(setType, id: id), exercise)
                            dismiss()
                        }
                    }
                }

                if workout.canEditSupersets, !exercise.checkInPending {
                    if let id = exercise.supersetID, workout.superset(id) != nil {
                        NavigationLink {
                            WatchSupersetEditor(id: id, selected: exercise, workout: workout, apply: apply)
                        } label: {
                            Label("Edit Superset", systemImage: "link")
                        }
                    } else if !exercise.isDone, !workout.supersetChoices(for: exercise).isEmpty {
                        NavigationLink {
                            chooseSuperset
                        } label: {
                            Label("Add to Superset", systemImage: "link")
                        }
                    }
                }

                if exercise.status == .active, !exercise.locked, !exercise.allSetsDone(), !exercise.checkInPending {
                    Button("Skip Exercise", systemImage: "forward.end", role: .destructive) {
                        confirmsSkip = true
                    }
                }

                Button("Skip Workout", systemImage: "forward.end.fill", role: .destructive) {
                    confirmsSkipWorkout = true
                }
                .confirmationDialog("Skip this workout?", isPresented: $confirmsSkipWorkout, titleVisibility: .visible) {
                    Button("Skip Workout", role: .destructive, action: onSkipWorkout)
                } message: {
                    Text("Logged sets are kept. Remaining sets are skipped.")
                }
            }
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .confirmationDialog(
                "Skip remaining sets for \(exercise.shownExercise?.exerciseName ?? "this exercise")?",
                isPresented: $confirmsSkip,
                titleVisibility: .visible
            ) {
                Button("Skip Exercise", role: .destructive) {
                    apply(.skip, exercise)
                    dismiss()
                }
            }
        }
    }

    private var chooseSuperset: some View {
        List {
            ForEach(workout.supersetChoices(for: exercise), id: \.first?.id) { group in
                if let target = group.first, let path = RowPath(target) {
                    Button {
                        apply(.joinSuperset(target: path, id: UUID()), exercise)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            if group.count > 1 {
                                Text("Superset \(workout.supersetLetter(for: group))")
                                    .foregroundStyle(SupersetStyle.color(at: target.supersetIndex ?? 0))
                            }
                            Text(group.compactMap { $0.shownExercise?.exerciseName }.joined(separator: ", "))
                                .font(group.count > 1 ? .footnote : .body)
                        }
                    }
                }
            }
        }
        .navigationTitle("Join Superset")
        .navigationBarTitleDisplayMode(.inline)
    }

}

private struct WatchSupersetEditor: View {
    @Environment(\.dismiss) private var dismiss

    let id: UUID
    let selected: WorkoutExercise
    let workout: Workout
    let apply: (WatchChange.ExerciseEdit, WorkoutExercise) -> Void

    var body: some View {
        let members = workout.superset(id) ?? []
        List {
            ForEach(members) { member in
                Text(member.shownExercise?.exerciseName ?? "Exercise")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { removeButton(member) }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) { removeButton(member) }
            }
            .onMove { source, destination in
                let ids = members.compactMap(\.syncID)
                guard ids.count == members.count else { return }
                apply(.reorderSuperset(id: id, members: ids, source: source, destination: destination), selected)
            }
        }
        .navigationTitle("Superset \(workout.supersetLetter(for: members))")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func removeButton(_ member: WorkoutExercise) -> some View {
        Button("Remove", systemImage: "xmark", role: .destructive) {
            apply(.leaveSuperset(id: id), member)
            if workout.superset(id) == nil || member === selected { dismiss() }
        }
    }
}
