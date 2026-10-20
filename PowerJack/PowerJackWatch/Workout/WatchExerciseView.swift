//
//  WatchExerciseView.swift
//  PowerJackWatch
//
//  One exercise's next set: tap weight or reps, turn the Digital Crown to change it,
//  and tap the check to log the set. The rest before it counts down at the top.
//

import SwiftData
import SwiftUI

struct WatchExerciseView: View {
    private enum Field {
        case weight, reps
    }

    @Bindable var workoutExercise: WorkoutExercise
    let onSetLogged: () -> Void

    @State private var entry: SetEntry?
    @FocusState private var focusedField: Field?

    private var exercise: Exercise? { workoutExercise.exercise }
    private var repsOnly: Bool { exercise?.repsOnly ?? false }
    private var workoutSet: WorkoutSet? { workoutExercise.nextSet }

    /// The rest running before this exercise's next set.
    private var rest: RestPeriod? {
        guard let workout = workoutExercise.workoutValue,
              workout.currentSet?.workoutExercise === workoutExercise
        else { return nil }
        return workout.currentRest
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(exercise?.exerciseName ?? "")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)

            if workoutExercise.checkInPending {
                Label("Check-in required", systemImage: "cross.case")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if let workoutSet, let entry = Binding($entry) {
                setHeader(workoutSet)
                valueBoxes(entry)
                logButtons(workoutSet)
            } else {
                doneSummary
            }
        }
        .frame(maxHeight: .infinity)
        .onChange(of: workoutSet?.id, initial: true) {
            entry = workoutSet.map { SetEntry(for: $0) }
            focusedField = repsOnly ? .reps : .weight
        }
    }

    private func setHeader(_ workoutSet: WorkoutSet) -> some View {
        HStack {
            Text(workoutExercise.setText(for: workoutSet))
                .foregroundStyle(workoutSet.isWarmup ? .secondary : .primary)
            Spacer()
            if let rest {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if rest.isResting(at: context.date) {
                        Label {
                            Text(timerInterval: rest.interval, countsDown: true)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "timer")
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
        }
        .font(.footnote)
    }

    private func valueBoxes(_ entry: Binding<SetEntry>) -> some View {
        HStack(spacing: 6) {
            if !repsOnly {
                valueBox(
                    entry.wrappedValue.weight.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)),
                    unit: entry.wrappedValue.unit.symbol,
                    field: .weight
                )
                .digitalCrownRotation(
                    entry.weightSteps,
                    from: 0,
                    through: entry.wrappedValue.maxWeightSteps,
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
            }

            valueBox("\(entry.wrappedValue.reps)", unit: "reps", field: .reps)
                .digitalCrownRotation(
                    Binding(
                        get: { Double(entry.wrappedValue.reps) },
                        set: { entry.wrappedValue.reps = Int($0.rounded()) }
                    ),
                    from: 1,
                    through: Double(WorkoutSet.maxReps),
                    by: 1,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
        }
    }

    /// Tapping a box points the Digital Crown at it.
    private func valueBox(_ value: String, unit: String, field: Field) -> some View {
        let isFocused = focusedField == field
        return VStack(spacing: 0) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.tint, lineWidth: 2)
                .opacity(isFocused ? 1 : 0)
        }
        .focusable()
        .focused($focusedField, equals: field)
        .onTapGesture { focusedField = field }
        .accessibilityElement(children: .combine)
    }

    private func logButtons(_ workoutSet: WorkoutSet) -> some View {
        HStack(spacing: 6) {
            if workoutSet.isWarmup {
                Button("Skip Warmups", systemImage: "forward") {
                    workoutExercise.skipWarmups()
                    onSetLogged()
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Skip warmups")
            }

            Button("Log Set", systemImage: "checkmark") {
                guard let entry else { return }
                workoutExercise.log(entry, on: workoutSet)
                onSetLogged()
            }
            .labelStyle(.iconOnly)
            .tint(.green)
            .buttonStyle(.borderedProminent)
            .disabled(entry?.weightTenthsPounds == nil && !repsOnly)
            .accessibilityLabel("Log \(workoutExercise.setText(for: workoutSet))")
        }
    }

    private var doneSummary: some View {
        VStack(spacing: 4) {
            Image(systemName: workoutExercise.status == .skipped ? "forward.circle.fill" : "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(workoutExercise.status == .skipped ? .secondary : Color.green)
            Text("\(workoutExercise.completedWorkingSets) of \(workoutExercise.workingSets.count) sets")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
