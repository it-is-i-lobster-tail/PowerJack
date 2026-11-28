//
//  ExerciseDetailView.swift
//  PowerJack
//
//  Created on 7/3/26.
//

import SwiftData
import SwiftUI

struct ExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSave: (Exercise) -> Void
    let exercise: Exercise

    @State private var draft: ExerciseDraft
    @State private var saveErrorMessage: String?
    /// Kept so the view never reads a deleted exercise while it closes.
    private let isOwn: Bool
    private let name: String
    /// Set while the remove choices show.
    @State private var usage: ExerciseRemoval.Usage?
    @State private var isPickingMergeTarget = false
    @State private var mergeTarget: Exercise?
    @State private var isConfirmingMerge = false
    @State private var setsToMerge = 0

    init(
        exercise: Exercise,
        onSave: @escaping (Exercise) -> Void = { _ in },
    ) {
        self.exercise = exercise
        self.onSave = onSave
        isOwn = exercise.userCreated
        name = exercise.exerciseName
        _draft = State(initialValue: ExerciseDraft(exercise: exercise))
    }

    var body: some View {
        content.traceScreen("Exercise Detail")
    }

    @ViewBuilder
    private var content: some View {
        ExerciseForm(
            draft: $draft,
            editExistingExercise: true,
            onSubmit: save
        )
        .saveErrorAlert($saveErrorMessage)
        .toolbar {
            // Every PowerJack has the built-ins, so only the lifter's own are worth sending or removing.
            if isOwn {
                ToolbarItem(placement: .topBarTrailing) {
                    SharedFileLink(file: SharedFile(exercise: exercise))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete Exercise", systemImage: "trash", action: askToRemove)
                }
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(name)\u{201D}?",
            isPresented: Binding(get: { usage != nil }, set: { if !$0 { usage = nil } }),
            titleVisibility: .visible,
            presenting: usage
        ) { usage in
            if !usage.isUsed {
                Button("Delete Exercise", role: .destructive) { remove { try ExerciseRemoval.delete(exercise, in: modelContext) } }
            }
            if exercise.isArchived {
                Button("Unarchive") { remove { try ExerciseRemoval.unarchive(exercise, in: modelContext) } }
            } else if usage.isUsed {
                Button("Archive") { remove { try ExerciseRemoval.archive(exercise, in: modelContext) } }
            }
            if usage.isUsed {
                Button("Merge Into Another Exercise") {
                    setsToMerge = usage.loggedSets
                    isPickingMergeTarget = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { usage in
            Text(Self.removeMessage(for: usage, isArchived: exercise.isArchived))
        }
        .sheet(isPresented: $isPickingMergeTarget, onDismiss: { isConfirmingMerge = mergeTarget != nil }) {
            ExerciseSelectionView(navigationTitle: "Merge Into", mode: .merge(exercise)) { mergeTarget = $0 }
        }
        .alert(
            "Merge into \u{201C}\(mergeTarget?.exerciseName ?? "")\u{201D}?",
            isPresented: $isConfirmingMerge,
            presenting: mergeTarget
        ) { target in
            Button("Merge", role: .destructive) { merge(into: target) }
            Button("Cancel", role: .cancel) { mergeTarget = nil }
        } message: { target in
            Text(Self.mergeMessage(source: name, target: target.exerciseName, sets: setsToMerge))
        }
    }

    static func removeMessage(for usage: ExerciseRemoval.Usage, isArchived: Bool) -> String {
        guard usage.isUsed else { return "This can\u{2019}t be undone." }
        let use = usage.loggedSets > 0
            ? "It has \(usage.loggedSets) logged \(usage.loggedSets == 1 ? "set" : "sets")."
            : "It\u{2019}s in a template or program."
        return isArchived
            ? "\(use) Merge it into another exercise to keep its history there."
            : "\(use) Archive it to hide it from search and keep its history, or merge it into another exercise."
    }

    static func mergeMessage(source: String, target: String, sets: Int) -> String {
        let moving = sets > 0
            ? "\(sets) logged \(sets == 1 ? "set moves" : "sets move")"
            : "Its templates and programs move"
        return "\(moving) from \u{201C}\(source)\u{201D} to \u{201C}\(target)\u{201D}, then \u{201C}\(source)\u{201D} is deleted. This can\u{2019}t be undone."
    }

    private func askToRemove() {
        do {
            usage = try ExerciseRemoval.usage(of: exercise, in: modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func merge(into target: Exercise) {
        mergeTarget = nil
        remove { try ExerciseRemoval.merge(exercise, into: target, in: modelContext) }
    }

    /// Runs a removal, then closes this screen.
    private func remove(_ removal: () throws -> Void) {
        do {
            try removal()
            usage = nil
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func save() {
        let originalDraft = ExerciseDraft(exercise: exercise)
        guard draft.apply(to: exercise) else { return }

        do {
            try modelContext.save()
            onSave(exercise)
            dismiss()
        } catch {
            _ = originalDraft.apply(to: exercise)
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview("ExerciseDetailView - Barbell") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ExerciseDetailView(
            exercise: scenario.exercises[0],
            onSave: { _ in },
        )
    }
}

#Preview("ExerciseDetailView - Bodyweight") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ExerciseDetailView(
            exercise: scenario.exercises[2],
            onSave: { _ in },
        )
    }
}

#Preview("ExerciseDetailView - Leg Press") {
    let scenario = PowerJackSeed.weekOneProgress()

    NavigationPreviewHost(modelContainer: scenario.container) {
        ExerciseDetailView(
            exercise: scenario.exercises[5],
            onSave: { _ in },
        )
    }
}
