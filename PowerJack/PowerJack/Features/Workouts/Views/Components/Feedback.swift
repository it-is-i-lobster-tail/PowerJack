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
    @State private var draft = FeedbackDraft()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exercise Feedback")
                        .font(.title2.bold())
                    Text("This helps calibrate weight, reps, and sets for next week.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                FeedbackScaleSection(
                    title: "Level of Effort",
                    subheading: "How difficult was this exercise to perform?",
                    selection: $draft.levelOfEffort
                )

                FeedbackScaleSection(
                    title: "Level of Pain",
                    subheading: "Pushing muscles is good, pain is not.",
                    selection: $draft.levelOfPain
                )
            }
            .padding(.vertical, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: draft.canSave) { wasComplete, isComplete in
            saveFeedbackIfComplete(wasComplete: wasComplete, isComplete: isComplete)
        }
    }

    private func saveFeedbackIfComplete(wasComplete: Bool, isComplete: Bool) {
        guard
            !wasComplete,
            isComplete,
            let levelOfEffort = draft.levelOfEffort,
            let levelOfPain = draft.levelOfPain
        else {
            return
        }

        let newFeedback = ExerciseFeedback(
            levelOfEffort: levelOfEffort,
            levelOfPain: levelOfPain
        )
        workoutExercise.addFeedback(feedback: newFeedback)
        if workoutExercise.status == .active {
            workoutExercise.completeAndCascade()
        }
        try? modelContext.save()
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
