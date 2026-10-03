//
//  RestTimerLiveActivity.swift
//  PowerJackWidgets
//
//  The rest timer in the Dynamic Island and on the Lock Screen. The countdown runs on its own;
//  once the activity goes stale (the end of the rest) it shows "Start set" instead.
//  Tapping it anywhere opens PowerJack on the current exercise.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(
                rest: context.state,
                workoutTitle: context.attributes.workoutTitle,
                isReady: context.isStale
            )
            .activityBackgroundTint(.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(RestActivityAttributes.currentExerciseURL)
        } dynamicIsland: { context in
            let rest = context.state
            let isReady = context.isStale

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RestRing(rest: rest, isReady: isReady, showsIcon: true)
                        .frame(width: 46, height: 46)
                        .padding(.leading, 4)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(rest: rest, isReady: isReady)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .padding(.trailing, 4)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 0) {
                        Text(isReady ? "Start set" : "Rest")
                            .font(.headline)
                            .foregroundStyle(RestPalette.tint(isReady: isReady))
                        Text(isReady ? "Your rest is over" : "Next set in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RestNextSet(rest: rest)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                RestRing(rest: rest, isReady: isReady, showsIcon: false)
                    .frame(width: 22, height: 22)
            } compactTrailing: {
                if isReady {
                    Text("Start set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RestPalette.tint(isReady: true))
                } else {
                    RestCountdown(rest: rest, isReady: false)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: 44)
                }
            } minimal: {
                RestRing(rest: rest, isReady: isReady, showsIcon: false)
            }
            .widgetURL(RestActivityAttributes.currentExerciseURL)
            .keylineTint(RestPalette.tint(isReady: isReady))
        }
    }
}

private enum RestPalette {
    static func tint(isReady: Bool) -> Color { isReady ? .green : .orange }
}

private struct RestLockScreenView: View {
    let rest: RestPeriod
    let workoutTitle: String
    let isReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RestRing(rest: rest, isReady: isReady, showsIcon: true)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 0) {
                    Text(isReady ? "Start set" : "Rest")
                        .font(.headline)
                        .foregroundStyle(RestPalette.tint(isReady: isReady))
                    Text(isReady ? "Your rest is over" : "Next set in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isReady {
                    Text("Start set")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.green, in: .capsule)
                } else {
                    RestCountdown(rest: rest, isReady: false)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }

            HStack(alignment: .lastTextBaseline) {
                RestNextSet(rest: rest)
                Spacer(minLength: 8)
                Text(workoutTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

private struct RestNextSet: View {
    let rest: RestPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(rest.exerciseName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(rest.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Counts down by itself; after the rest it holds at 0:00 until the activity goes stale.
private struct RestCountdown: View {
    let rest: RestPeriod
    let isReady: Bool

    var body: some View {
        Group {
            if isReady {
                Text("0:00")
            } else {
                Text(timerInterval: rest.interval, countsDown: true)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .foregroundStyle(RestPalette.tint(isReady: isReady))
    }
}

private struct RestRing: View {
    let rest: RestPeriod
    let isReady: Bool
    let showsIcon: Bool

    var body: some View {
        if isReady {
            ZStack {
                Circle()
                    .fill(RestPalette.tint(isReady: true).opacity(0.25))
                Image(systemName: "dumbbell.fill")
                    .font(showsIcon ? .title3 : .caption2)
                    .foregroundStyle(RestPalette.tint(isReady: true))
            }
        } else {
            ProgressView(timerInterval: rest.interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                if showsIcon {
                    Image(systemName: "timer")
                        .foregroundStyle(RestPalette.tint(isReady: false))
                }
            }
            .progressViewStyle(.circular)
            .tint(RestPalette.tint(isReady: false))
        }
    }
}

// MARK: Previews

private extension RestActivityAttributes {
    static let preview = RestActivityAttributes(workoutTitle: "Day 2 · Week 1")
}

private extension RestPeriod {
    static let preview = RestPeriod(
        startedAt: .now,
        endsAt: .now.addingTimeInterval(180),
        exerciseName: "Barbell Back Squat",
        setNumber: 2,
        setCount: 3,
        reps: 8,
        weightTenthsPounds: 2250
    )
}

#Preview("Lock Screen", as: .content, using: RestActivityAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestPeriod.preview
}

#Preview("Island Compact", as: .dynamicIsland(.compact), using: RestActivityAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestPeriod.preview
}

#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: RestActivityAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestPeriod.preview
}

#Preview("Island Minimal", as: .dynamicIsland(.minimal), using: RestActivityAttributes.preview) {
    RestTimerLiveActivity()
} contentStates: {
    RestPeriod.preview
}
