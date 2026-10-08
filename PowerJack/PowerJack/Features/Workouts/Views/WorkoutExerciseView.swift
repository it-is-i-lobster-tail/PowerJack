//
//  WorkoutExerciseView.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import SwiftData
import SwiftUI

struct WorkoutExerciseView: View {
    /// Lets the last warmup's check draw in before the group folds away.
    private static let warmupCollapseDelay = 0.35
    private static let warmupCollapseDuration = 0.3

    let onSetsDone: (WorkoutExercise) -> Void
    let screenWidth: CGFloat
    let focusedSetField: FocusState<FocusedSetField?>.Binding

    @Bindable var workoutExercise: WorkoutExercise
    @Environment(\.logSetHint) private var logSetHint

    // Finished warmups fold away, then the heading gets a check.
    @State private var warmupsCollapsed: Bool
    @State private var warmupsChecked: Bool

    init(
        onSetsDone: @escaping (WorkoutExercise) -> Void,
        screenWidth: CGFloat,
        focusedSetField: FocusState<FocusedSetField?>.Binding,
        workoutExercise: WorkoutExercise
    ) {
        self.onSetsDone = onSetsDone
        self.screenWidth = screenWidth
        self.focusedSetField = focusedSetField
        self.workoutExercise = workoutExercise
        _warmupsCollapsed = State(initialValue: workoutExercise.warmupsDone)
        _warmupsChecked = State(initialValue: workoutExercise.warmupsDone)
    }

    /// The hint only shows on the exercise the lifter starts with.
    private var shownLogSetHint: LogSetHint? {
        guard workoutExercise.workoutValue?.currentSet?.workoutExercise === workoutExercise else { return nil }
        return logSetHint
    }

    var body: some View {
        VStack {
            VStack(alignment: .center) {
                Text(workoutExercise.exercise?.exerciseName ?? "")
                    .font(.title)
                    .foregroundStyle(.primary)
                Text(workoutExercise.exercise?.exerciseEquipment.rawValue.localizedCapitalized ?? "")
                    .font(.default)
                    .foregroundStyle(.primary)
                if workoutExercise.checkInPending {
                    Label("Check-in required", systemImage: "cross.case")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let shownLogSetHint {
                HintView(shownLogSetHint)
                    .frame(width: screenWidth * 0.88)
            }

            ScrollView {
                VStack(spacing: 0) {
                    if workoutExercise.showsWarmups {
                        warmupGroup
                    }

                    groupHeader(.working, isDone: workoutExercise.allSetsDone())
                    setRows(workoutExercise.workingSets)
                        .padding(.top, LayoutMetrics.compactSpacing)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: workoutExercise.allSetsDone()) { wasDone, isDone in
            guard !wasDone, isDone else { return }
            focusedSetField.wrappedValue = nil
            onSetsDone(workoutExercise)
        }
        .onChange(of: workoutExercise.warmupsDone) { _, isDone in
            isDone ? collapseWarmups() : expandWarmups()
        }
    }

    private var warmupGroup: some View {
        VStack(spacing: 0) {
            // Once every warmup is done, tapping WARMUP shows or hides them.
            groupHeader(
                .warmup,
                isDone: warmupsChecked,
                onTitleTap: warmupTitleTap
            )

            // Full width and clipped, so the sets slide up under the heading as the group closes.
            VStack(spacing: 0) {
                if !warmupsCollapsed {
                    setRows(workoutExercise.warmupSets)
                        .padding(.vertical, LayoutMetrics.compactSpacing)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
        }
    }

    private func groupHeader(
        _ setType: SetType,
        isDone: Bool = false,
        onTitleTap: (() -> Void)? = nil
    ) -> some View {
        SetGroupHeader(workoutExercise: workoutExercise, setType: setType, isDone: isDone, onTitleTap: onTitleTap)
            .frame(width: screenWidth * 0.84)
    }

    private func setRows(_ sets: [WorkoutSet]) -> some View {
        VStack(spacing: LayoutMetrics.compactSpacing) {
            ForEach(sets) { workoutSet in
                WorkoutSetView(
                    focusedSetField: focusedSetField,
                    workoutSet: workoutSet,
                    repsOnly: workoutExercise.exercise?.repsOnly ?? false,
                    number: workoutExercise.number(of: workoutSet),
                    isLastSet: workoutSet === workoutExercise.workoutSets.last,
                    onWeightChange: { weight in
                        workoutExercise.applyWeight(weight, after: workoutSet)
                    },
                    // A finished set closes the keyboard; the next set waits for a tap.
                    onAutoComplete: { focusedSetField.wrappedValue = nil }
                )
                .frame(width: screenWidth * 0.88, height: 55)

                // No divider at the end of a group; the next group's heading separates them.
                if workoutSet !== sets.last {
                    Color.gray.opacity(0.2)
                        .frame(width: screenWidth * 0.75, height: 1)
                }
            }
        }
    }

    private func collapseWarmups() {
        withAnimation(.easeInOut(duration: Self.warmupCollapseDuration).delay(Self.warmupCollapseDelay)) {
            warmupsCollapsed = true
        } completion: {
            // A warmup added back mid-animation keeps the group open and unchecked.
            guard workoutExercise.warmupsDone else { return }
            withAnimation { warmupsChecked = true }
        }
    }

    private var warmupTitleTap: (() -> Void)? {
        workoutExercise.warmupsDone ? { toggleWarmups() } : nil
    }

    /// Opens or closes finished warmups with the same animation as the automatic collapse.
    private func toggleWarmups() {
        withAnimation(.easeInOut(duration: Self.warmupCollapseDuration)) {
            warmupsCollapsed.toggle()
        }
    }

    private func expandWarmups() {
        warmupsChecked = false
        withAnimation(.easeInOut(duration: Self.warmupCollapseDuration)) {
            warmupsCollapsed = false
        }
    }
}
