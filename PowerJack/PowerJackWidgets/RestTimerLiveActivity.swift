//
//  RestTimerLiveActivity.swift
//  PowerJackWidgets
//
//  The active workout in the Dynamic Island and on the Lock Screen: the current set, its target,
//  and a check to log it at that target. Between sets of an exercise the rest counts down on its own;
//  once the activity goes stale (the end of the rest) it shows "Start set" instead.
//  Tapping anywhere else opens PowerJack on the current exercise.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            WorkoutLockScreenView(state: context.state, phase: RestPhase(context))
            .activityBackgroundTint(.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(RestActivityAttributes.currentExerciseURL)
        } dynamicIsland: { context in
            let state = context.state
            let phase = RestPhase(context)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityBadge(phase: phase)
                        .frame(width: 46, height: 46)
                        .padding(.leading, 4)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestStatus(phase: phase)
                        .font(phase == .ready ? .headline : .system(size: 30, weight: .semibold, design: .rounded))
                        // Room for "9:59" next to a long exercise name.
                        .frame(width: phase == .none ? 0 : 84, alignment: .trailing)
                        .padding(.trailing, 4)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.center) {
                    SetHeading(state: state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SetTargets(state: state)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                PowerJackMark()
                    .frame(height: 16)
                    .padding(.leading, 2)
            } compactTrailing: {
                switch phase {
                case .resting:
                    RestStatus(phase: phase)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: 44)
                case .ready:
                    RestStatus(phase: phase)
                        .font(.caption.weight(.semibold))
                case .none:
                    Text("Set \(state.setOrder + 1)")
                        .font(.caption.weight(.semibold))
                }
            } minimal: {
                ActivityBadge(phase: phase)
            }
            .widgetURL(RestActivityAttributes.currentExerciseURL)
            .keylineTint(RestPalette.tint(for: phase))
        }
    }
}

/// Where the rest before the current set stands.
private enum RestPhase: Equatable {
    /// No rest: the start of the workout or of a new exercise.
    case none
    case resting(ClosedRange<Date>)
    /// The rest ran out and the set is waiting.
    case ready

    init(_ context: ActivityViewContext<RestActivityAttributes>) {
        if let rest = context.state.rest {
            self = context.isStale ? .ready : .resting(rest)
        } else {
            self = .none
        }
    }
}

private enum RestPalette {
    static func tint(for phase: RestPhase) -> Color {
        switch phase {
        case .none: .white
        case .resting: .orange
        case .ready: .green
        }
    }
}

private struct WorkoutLockScreenView: View {
    let state: WorkoutActivityState
    let phase: RestPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ActivityBadge(phase: phase)
                    .frame(width: 44, height: 44)

                SetHeading(state: state)

                Spacer(minLength: 8)

                RestStatus(phase: phase)
                    .font(phase == .ready
                          ? .subheadline.weight(.semibold)
                          : .system(size: 30, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 120, alignment: .trailing)
            }

            SetTargets(state: state)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

private struct SetHeading: View {
    let state: WorkoutActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.exerciseName)
                .font(.headline)
                .lineLimit(1)
            Text(state.setText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Every set of the exercise side by side, the current one highlighted,
/// and the check that logs the current set at exactly its target.
private struct SetTargets: View {
    let state: WorkoutActivityState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(state.sets.enumerated()), id: \.offset) { _, activitySet in
                SetChip(activitySet: activitySet, repsOnly: state.repsOnly)
            }

            Spacer(minLength: 0)

            if state.canCompleteAtTarget {
                Button(intent: CompleteSetIntent(exerciseOrder: state.exerciseOrder, setOrder: state.setOrder)) {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(.green, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete set at target")
            }
        }
    }
}

/// One set: its label ("W1" for a warmup), then weight and reps. Done sets show what was logged, the rest their target.
private struct SetChip: View {
    let activitySet: ActivitySet
    let repsOnly: Bool

    private var isCurrent: Bool { activitySet.progress == .current }
    private var isFinished: Bool { activitySet.progress == .done || activitySet.progress == .skipped }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Text(activitySet.label)
                switch activitySet.progress {
                case .done:
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                case .skipped:
                    Image(systemName: "forward.fill")
                default:
                    EmptyView()
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            Text(activitySet.weightText(repsOnly: repsOnly))
                .font(.subheadline.weight(.semibold))
            Text("× \(activitySet.repsText)")
                .font(.caption)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: 58)
        .padding(.vertical, 5)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.16))
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
            }
        }
        .opacity(isFinished ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// The countdown while resting, "Start set" once the rest is over, and nothing without a rest.
/// The countdown runs by itself, so it needs no updates.
private struct RestStatus: View {
    let phase: RestPhase

    var body: some View {
        Group {
            switch phase {
            case .none:
                EmptyView()
            case .resting(let rest):
                Text(timerInterval: rest, countsDown: true, showsHours: false)
                    .monospacedDigit()
            case .ready:
                Text("Start set")
            }
        }
        .multilineTextAlignment(.trailing)
        .foregroundStyle(RestPalette.tint(for: phase))
    }
}

private struct PowerJackMark: View {
    var body: some View {
        Image("PowerJackMark")
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

/// The PJ mark, ringed by the rest's progress while resting and on a green disc once it is over.
private struct ActivityBadge: View {
    let phase: RestPhase

    var body: some View {
        Group {
            switch phase {
            case .none:
                Circle()
                    .fill(.white.opacity(0.12))
            case .resting(let rest):
                ProgressView(timerInterval: rest, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(RestPalette.tint(for: phase))
            case .ready:
                Circle()
                    .fill(RestPalette.tint(for: phase).opacity(0.25))
            }
        }
        .overlay {
            PowerJackMark()
                .scaleEffect(0.5)
        }
    }
}

// MARK: Previews

private extension RestActivityAttributes {
    static let preview = RestActivityAttributes(workoutTitle: "Day 2 · Week 2")
}

private extension WorkoutActivityState {
    static let resting = WorkoutActivityState(
        exerciseName: "Barbell Back Squat",
        setText: "Set 1 of 3",
        exerciseOrder: 0,
        setOrder: 1,
        sets: [
            ActivitySet(label: "W1", progress: .done, reps: 9, weightTenthsPounds: 2250),
            ActivitySet(label: "1", progress: .current, reps: 8, weightTenthsPounds: 2250),
            ActivitySet(label: "2", progress: .upcoming, reps: 8, weightTenthsPounds: 2250),
            ActivitySet(label: "3", progress: .upcoming, reps: 7, weightTenthsPounds: 2300),
        ],
        repsOnly: false,
        canCompleteAtTarget: true,
        rest: .now ... .now.addingTimeInterval(180)
    )

    static let firstWeek = WorkoutActivityState(
        exerciseName: "Barbell Back Squat",
        setText: "Set 1 of 2",
        exerciseOrder: 0,
        setOrder: 0,
        sets: [
            ActivitySet(label: "1", progress: .current, reps: nil, weightTenthsPounds: nil),
            ActivitySet(label: "2", progress: .upcoming, reps: nil, weightTenthsPounds: nil),
        ],
        repsOnly: false,
        canCompleteAtTarget: false,
        rest: nil
    )
}

#Preview("Lock Screen", as: .content, using: RestActivityAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    WorkoutActivityState.resting
    WorkoutActivityState.firstWeek
}

#Preview("Island Compact", as: .dynamicIsland(.compact), using: RestActivityAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    WorkoutActivityState.resting
    WorkoutActivityState.firstWeek
}

#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: RestActivityAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    WorkoutActivityState.resting
    WorkoutActivityState.firstWeek
}

#Preview("Island Minimal", as: .dynamicIsland(.minimal), using: RestActivityAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    WorkoutActivityState.resting
    WorkoutActivityState.firstWeek
}
