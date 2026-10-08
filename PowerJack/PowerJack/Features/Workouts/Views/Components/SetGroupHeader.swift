//
//  SetGroupHeader.swift
//  PowerJack
//
//  Created by Claude on 10/7/26.
//

import SwiftData
import SwiftUI

/// The heading above a group of sets, with a menu to add, remove or skip sets in that group.
struct SetGroupHeader: View {
    let workoutExercise: WorkoutExercise
    let setType: SetType
    /// Shows the green check once every set in the group is done.
    var isDone = false
    /// Makes the title tappable, e.g. to show or hide finished warmups.
    var onTitleTap: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.workoutIsReadOnly) private var isReadOnly

    private var title: String { setType == .warmup ? "Warmup" : "Working Sets" }
    private var isLocked: Bool { workoutExercise.locked }

    var body: some View {
        HStack {
            if let onTitleTap {
                Button(action: onTitleTap) { titleLabel }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows or hides the sets")
            } else {
                titleLabel
            }

            Spacer()

            if !isReadOnly {
                Menu {
                    switch setType {
                    case .warmup: warmupActions
                    case .working: workingActions
                    }
                } label: {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 36)
                        .contentShape(.rect)
                }
                .accessibilityLabel("\(title) options")
            }
        }
        .padding(.vertical, LayoutMetrics.compactSpacing / 2)
    }

    private var titleLabel: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Sized to the title so the heading keeps its height when the check appears.
            if isDone {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
                    .transition(.symbolEffect(.drawOn, options: .speed(2.2)))
                    .accessibilityLabel("\(title) done")
            }
        }
        // Draws the check in when a group finishes, whatever finished it.
        .animation(.default, value: isDone)
        // The whole heading height is tappable, not just the glyphs.
        .frame(minHeight: 36)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var warmupActions: some View {
        Button("Add Warmup Set", systemImage: "plus") {
            update { _ = workoutExercise.addWarmupSet() }
        }
        .disabled(isLocked || workoutExercise.warmupSets.count >= WorkoutExercise.maxWarmupSets)

        Button("Remove Warmup Set", systemImage: "minus") {
            update { workoutExercise.removeLastSet(type: .warmup) }
        }
        .disabled(!workoutExercise.canRemoveSet(type: .warmup))

        Divider()

        Button("Disable Warmup for Exercise", systemImage: "nosign") {
            withAnimation { update { workoutExercise.disableWarmups() } }
        }
        .disabled(isLocked)

        Button("Skip Warmup", systemImage: "forward") {
            update { workoutExercise.skipWarmups() }
        }
        .disabled(isLocked || workoutExercise.warmupSets.allSatisfy(\.isDone))
    }

    @ViewBuilder
    private var workingActions: some View {
        Button("Add Set", systemImage: "plus") {
            update { _ = workoutExercise.addSet() }
        }
        .disabled(isLocked || workoutExercise.workingSets.count >= WorkoutExercise.maxSets)

        Button("Remove Last Set", systemImage: "minus") {
            update { workoutExercise.removeLastSet() }
        }
        .disabled(!workoutExercise.canRemoveSet(type: .working))

        Divider()

        Button("Skip Remaining Sets", systemImage: "forward") {
            update { workoutExercise.skipAndCascade() }
        }
        .disabled(isLocked)
    }

    private func update(_ change: () -> Void) {
        change()
        try? modelContext.save()
    }
}
