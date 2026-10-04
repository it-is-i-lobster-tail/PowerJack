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
                          : .system(size: 36, weight: .semibold, design: .rounded))
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

/// The set's target weight and reps, and the check that logs it at exactly that target.
private struct SetTargets: View {
    let state: WorkoutActivityState

    var body: some View {
        HStack(spacing: 24) {
            TargetValue(label: "Weight", value: state.targetWeightText)
            TargetValue(label: "Reps", value: state.targetRepsText)

            Spacer(minLength: 8)

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
        .frame(minHeight: 44)
    }
}

private struct TargetValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
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
        exerciseOrder: 0,
        setOrder: 1,
        setCount: 3,
        targetReps: 8,
        targetWeightTenthsPounds: 2250,
        repsOnly: false,
        canCompleteAtTarget: true,
        rest: .now ... .now.addingTimeInterval(180)
    )

    static let firstWeek = WorkoutActivityState(
        exerciseName: "Barbell Back Squat",
        exerciseOrder: 0,
        setOrder: 0,
        setCount: 2,
        targetReps: nil,
        targetWeightTenthsPounds: nil,
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
