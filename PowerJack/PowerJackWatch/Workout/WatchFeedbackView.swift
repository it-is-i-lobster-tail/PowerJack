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
    @Environment(WatchSync.self) private var sync

    @Bindable var workoutExercise: WorkoutExercise
    let onFinished: () -> Void

    @State private var draft: FeedbackDraft

    init(workoutExercise: WorkoutExercise, onFinished: @escaping () -> Void) {
        self.workoutExercise = workoutExercise
        self.onFinished = onFinished
        _draft = State(initialValue: FeedbackDraft(for: workoutExercise))
    }

    var body: some View {
        // Each answer brings up the next question; the last one saves and moves on straight away.
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
        .navigationTitle(workoutExercise.shownExercise?.exerciseName ?? "Feedback")
        .interactiveDismissDisabled()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: draft.canSave) { _, canSave in
            if canSave { save() }
        }
    }

    /// Whether a question came before this one, so Back can return to it.
    private var canGoBack: Bool {
        draft.topSetRepsInReserve != nil || draft.repsInReserve != nil || draft.levelOfEffort != nil
    }

    /// Clears the last answer given, which brings its question back.
    private func goBack() {
        if draft.ratesRepsInReserve, draft.repsInReserve != nil {
            draft.repsInReserve = nil
        } else if !draft.ratesRepsInReserve, draft.levelOfEffort != nil {
            draft.levelOfEffort = nil
        } else {
            draft.topSetRepsInReserve = nil
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

            if canGoBack {
                Button("Back", systemImage: "chevron.backward") {
                    withAnimation { goBack() }
                }
                .foregroundStyle(.secondary)
            }
        }
        .id(title)
    }

    private func save() {
        guard let feedback = draft.makeFeedback() else { return }
        sync.perform { $0.rate(workoutExercise, feedback: feedback, topSet: draft.topSetRepsInReserve) }
        onFinished()
    }
}
