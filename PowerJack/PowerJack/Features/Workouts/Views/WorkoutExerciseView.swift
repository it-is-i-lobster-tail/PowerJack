//
//  WorkoutExerciseView.swift
//  PowerJack
//
//  Created on 6/24/26.
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

    @AppStorage(AppSettings.Key.hints) private var hintsEnabled = AppSettings.Default.hints
    // Read once on appear; it looks up the lifter's first logged set.
    /// Grows with the text size, so large text still fits a set row.
    @ScaledMetric private var setRowHeight = 55.0
    @State private var showsWarmupHint = false

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

    var body: some View {
        // The exercise's name and equipment are in the header bubble above.
        ScrollView {
            VStack(spacing: 0) {
                notes

                if workoutExercise.showsWarmups {
                    warmupGroup
                }

                groupHeader(.working, isDone: workoutExercise.allSetsDone())
                setRows(workoutExercise.workingSets)
                    .padding(.top, LayoutMetrics.compactSpacing)
            }
            .frame(maxWidth: .infinity)
            // Room below the bar, inside the scroll content so the system's soft fade under the bar
            // doesn't reach the first line.
            .padding(.top, 26)
            .padding(.bottom, LayoutMetrics.compactSpacing)
        }
        // The number pad slides over the sets, so the one being typed in scrolls up above it.
        .keepsFocusAboveKeyboard(focusedSetField.wrappedValue?.setID)
        .onChange(of: workoutExercise.allSetsDone()) { wasDone, isDone in
            guard !wasDone, isDone else { return }
            focusedSetField.wrappedValue = nil
            onSetsDone(workoutExercise)
        }
        .onChange(of: workoutExercise.warmupsDone) { _, isDone in
            isDone ? collapseWarmups() : expandWarmups()
        }
        .onAppear {
            showsWarmupHint = workoutExercise.showsWarmupHint
        }
    }

    /// What's special about this exercise today, above its sets.
    private var notes: some View {
        VStack(spacing: 4) {
            if let substituteText {
                Label(substituteText, systemImage: "arrow.triangle.swap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if workoutExercise.checkInPending {
                Label("Check-in required", systemImage: "cross.case")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ProgressionCue(workoutExercise: workoutExercise)
        }
    }

    /// e.g. "Sub for Bench Press · this week".
    private var substituteText: String? {
        guard workoutExercise.substitute != nil, let planned = workoutExercise.exercise else { return nil }
        return "Sub for \(planned.exerciseName) · this week"
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
                    VStack(spacing: 0) {
                        // Folds away with the warmups it explains.
                        if hintsEnabled && showsWarmupHint {
                            Text(WorkoutExercise.warmupHint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(width: screenWidth * 0.84, alignment: .leading)
                        }
                        setRows(workoutExercise.warmupSets)
                            .padding(.vertical, LayoutMetrics.compactSpacing)
                    }
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
        let currentSet = workoutExercise.supersetID == nil ? nil : workoutExercise.workoutValue?.currentSet?.workoutSet
        return VStack(spacing: LayoutMetrics.compactSpacing) {
            ForEach(sets) { workoutSet in
                WorkoutSetView(
                    focusedSetField: focusedSetField,
                    workoutSet: workoutSet,
                    repsOnly: workoutExercise.shownExercise?.repsOnly ?? false,
                    number: workoutExercise.number(of: workoutSet),
                    onWeightChange: { weight, previousWeight in
                        // A top set's weight is heavier than the back sets that follow it.
                        guard !workoutExercise.isTopSet(workoutSet) else { return }
                        workoutExercise.applyWeight(weight, after: workoutSet, replacing: previousWeight)
                    }
                )
                .frame(width: screenWidth * 0.88)
                .frame(minHeight: setRowHeight)
                .overlay(alignment: .leading) {
                    if workoutSet === currentSet {
                        Capsule()
                            .fill(workoutExercise.supersetColor ?? .accentColor)
                            .frame(width: 3)
                            .padding(.vertical, 8)
                            .accessibilityHidden(true)
                    }
                }
                .id(workoutSet.id)

                if workoutExercise.needsTopSetRating, workoutExercise.isLastTopSet(workoutSet) {
                    TopSetRating(workoutExercise: workoutExercise)
                        .frame(width: screenWidth * 0.84)
                        .padding(.vertical, LayoutMetrics.compactSpacing)
                        .transition(.opacity)
                }

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
