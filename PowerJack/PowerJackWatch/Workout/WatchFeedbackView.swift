//
//  WatchFeedbackView.swift
//  PowerJackWatch
//
//  The same questions the iPhone asks once an exercise's sets are logged, one at a time.
//  The answers set next week's weight, reps and sets.
//

import SwiftData
import SwiftUI

struct WatchFeedbackView: View {
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
        // Each answer brings up the next question; the last one saves.
        Group {
            if draft.asksTopSet && draft.topSetRepsInReserve == nil {
                question("Top set: reps left?", selection: $draft.topSetRepsInReserve)
            } else if draft.ratesRepsInReserve && draft.repsInReserve == nil {
                question("Last set: reps left?", selection: $draft.repsInReserve)
            } else if !draft.ratesRepsInReserve && draft.levelOfEffort == nil {
                question("How hard was it?", selection: $draft.levelOfEffort)
            } else {
                question("Any pain?", selection: $draft.levelOfPain)
            }
        }
        .navigationTitle(workoutExercise.exercise?.exerciseName ?? "Feedback")
        .interactiveDismissDisabled()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: draft.canSave) { _, canSave in
            if canSave { save() }
        }
    }

    private func question<Option: ScaleSelectorOption & Identifiable>(
        _ title: String,
        selection: Binding<Option?>
    ) -> some View {
        List {
            Section {
                ForEach(Array(Option.allCases)) { option in
                    Button {
                        withAnimation { selection.wrappedValue = option }
                    } label: {
                        HStack {
                            Text(option.valueText)
                                .font(.headline)
                                .monospacedDigit()
                                .frame(width: 24, alignment: .leading)
                            Text(option.label)
                        }
                    }
                }
            } header: {
                Text(title)
                    .font(.headline)
                    .textCase(nil)
            }
        }
        .id(title)
    }

    private func save() {
        guard let feedback = draft.makeFeedback() else { return }
        if let topSetRepsInReserve = draft.topSetRepsInReserve {
            workoutExercise.rateTopSets(topSetRepsInReserve)
        }
        workoutExercise.addFeedback(feedback: feedback)
        onFinished()
    }
}
