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

    init(workoutExercise: WorkoutExercise, onFinished: @escaping () -> Void) {
        self.workoutExercise = workoutExercise
        self.onFinished = onFinished
        _draft = State(initialValue: FeedbackDraft(
            ratesRepsInReserve: workoutExercise.templateType?.ratesRepsInReserve ?? false,
            asksTopSet: workoutExercise.topSetsNeedRating
        ))
    }

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
        .onChange(of: draft.canSave) { wasComplete, isComplete in
            saveFeedbackIfComplete(wasComplete: wasComplete, isComplete: isComplete)
        }
    }

    private func saveFeedbackIfComplete(wasComplete: Bool, isComplete: Bool) {
        guard !wasComplete, isComplete, let newFeedback = draft.makeFeedback() else {
            return
        }

        if let topSetRepsInReserve = draft.topSetRepsInReserve {
            workoutExercise.rateTopSets(topSetRepsInReserve)
        }
        // The exercise stays open, so the lifter can still add a set before finishing the workout.
        workoutExercise.addFeedback(feedback: newFeedback)
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
