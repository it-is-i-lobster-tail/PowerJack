//
//  Feedback.swift
//  PowerJack
//
//  Created by trogdor on 7/15/26.
//

import SwiftData
import SwiftUI

struct Feedback: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var workoutExercise: WorkoutExercise
    let onFinished: () -> Void
    @State private var draft: FeedbackDraft
    /// The answers wait this long, with Undo, before they're saved and the workout moves on.
    static let undoWindow: Duration = .seconds(4)
    @State private var pendingSave: Task<Void, Never>?

    init(workoutExercise: WorkoutExercise, onFinished: @escaping () -> Void) {
        self.workoutExercise = workoutExercise
        self.onFinished = onFinished
        _draft = State(initialValue: FeedbackDraft(for: workoutExercise))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    // The exercise's name is the title, so the lifter always knows what they're rating.
                    Text(workoutExercise.shownExercise?.exerciseName ?? "Exercise Feedback")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Your answers set next week's weight, reps, and sets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if draft.asksTopSet {
                    FeedbackScaleSection(
                        title: "Top Set",
                        subheading: "How many more good reps could you have done on your top set?",
                        selection: $draft.topSetRepsInReserve
                    )
                }

                if draft.ratesRepsInReserve {
                    FeedbackScaleSection(
                        title: "Reps Left",
                        subheading: "How many more good reps could you have done on your last set?",
                        selection: $draft.repsInReserve
                    )
                } else {
                    FeedbackScaleSection(
                        title: "Level of Effort",
                        subheading: "How difficult was this exercise to perform?",
                        selection: $draft.levelOfEffort
                    )
                }

                FeedbackScaleSection(
                    title: "Level of Pain",
                    subheading: "Pushing muscles is good, pain is not.",
                    selection: $draft.levelOfPain
                )
            }
            .padding(.vertical, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if pendingSave != nil {
                savedBar
                    .transition(.opacity)
            }
        }
        .animation(.default, value: pendingSave != nil)
        .onChange(of: draft.canSave) { wasComplete, isComplete in
            if isComplete, !wasComplete { saveSoon() }
        }
        // Answered on the watch first, so this sheet closes without saving its own.
        .onDisappear { pendingSave?.cancel() }
    }

    private var savedBar: some View {
        HStack {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Spacer()
            Button("Undo", action: undo)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, LayoutMetrics.sectionSpacing)
        .padding(.vertical, LayoutMetrics.compactSpacing)
        .powerJackGlassCard(interactive: true)
        .padding(.bottom, LayoutMetrics.compactSpacing)
    }

    /// The last answer moves on by itself after a moment, unless the lifter takes it back.
    private func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: Self.undoWindow)
            guard !Task.isCancelled else { return }
            saveFeedback()
        }
    }

    /// Takes back the last question's answer, so any answer can be changed before it's saved.
    private func undo() {
        pendingSave?.cancel()
        pendingSave = nil
        draft.levelOfPain = nil
    }

    private func saveFeedback() {
        guard let newFeedback = draft.makeFeedback() else { return }

        // The exercise stays open, so the lifter can still add a set before finishing the workout.
        workoutExercise.answerFeedback(newFeedback, topSet: draft.topSetRepsInReserve)
        modelContext.saveTraced("feedback answered")
        dismiss()
        onFinished()
    }
}

private struct FeedbackScaleSection<Option: ScaleSelectorOption>: View {
    let title: String
    let subheading: String
    @Binding var selection: Option?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subheading)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ScaleSelector(selection: $selection)
        }
    }
}

#Preview("Feedback") {
    let scenario = PowerJackSeed.weekOneProgress()

    Feedback(
        workoutExercise: scenario.weekOneWorkouts[1].workoutExercises[0],
        onFinished: {}
    )
    .padding(.horizontal, LayoutMetrics.sectionSpacing)
    .modelContainer(scenario.container)
}
