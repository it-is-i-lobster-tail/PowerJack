//
//  RestLiveActivityController.swift
//  PowerJack
//
//  Keeps the workout Live Activity (Dynamic Island + Lock Screen) in step with the current set and rest.
//

import ActivityKit
import Foundation
import OSLog

enum RestLiveActivityController {
    /// Starts, updates, or ends the Live Activity so it shows `state`.
    /// iOS only lets an app start one while it is in the foreground.
    static func sync(state: WorkoutActivityState?, workoutTitle: String?, isEnabled: Bool) async {
        // Previews render seed data and should never start a real activity.
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        let running = Activity<RestActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }

        guard isEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let state,
              let workoutTitle
        else {
            if !running.isEmpty { TraceLog.record(.timer, "Live Activity ended (\(running.count))") }
            await end(running)
            return
        }

        let attributes = RestActivityAttributes(workoutTitle: workoutTitle)

        if let activity = running.first(where: { $0.attributes == attributes }) {
            await end(running.filter { $0.id != activity.id })
            let content = contentWithCurrentHeartRate(state)
            if activity.content.state != content.state {
                TraceLog.record(.timer, "Live Activity updated: \(state.setText), resting \(state.rest != nil)")
                await activity.update(content)
            }
            return
        }

        await end(running)
        do {
            _ = try Activity.request(attributes: attributes, content: contentWithCurrentHeartRate(state))
            TraceLog.record(.timer, "Live Activity started: \(state.setText)")
        } catch {
            Logger.restTimer.error("Could not start the workout Live Activity: \(error.localizedDescription)")
            TraceLog.record(.timer, "Could not start the Live Activity: \(TraceLog.describe(error))")
        }
    }

    /// Updates an existing activity when HealthKit delivers a sample while the app is backgrounded.
    static func refreshHeartRate() async {
        for activity in Activity<RestActivityAttributes>.activities
        where activity.activityState == .active || activity.activityState == .stale {
            let content = contentWithCurrentHeartRate(activity.content.state)
            if content.state != activity.content.state {
                await activity.update(content)
            }
        }
    }

    private static func contentWithCurrentHeartRate(_ state: WorkoutActivityState) -> ActivityContent<WorkoutActivityState> {
        var state = state
        state.heartRateBPM = WorkoutHeartRate.shared.bpm
        return ActivityContent(state: state, staleDate: state.rest?.upperBound)
    }

    /// Brings the activity in line with `program`'s current workout, for changes made while
    /// PowerJack's screens may not be running to notice: a check on the Lock Screen, a set logged
    /// or a workout finished on the watch.
    static func follow(_ program: Program?) async {
        let workout = program?.nextWorkout
        await sync(
            state: workout?.activityState(),
            workoutTitle: workout.flatMap { program?.activityTitle(for: $0) },
            isEnabled: UserDefaults.standard.object(forKey: AppSettings.Key.restLiveActivity) as? Bool
                ?? AppSettings.Default.restLiveActivity
        )
    }

    /// Ends every activity as PowerJack closes. iOS ends the app as soon as it returns from
    /// `applicationWillTerminate`, so this waits there, for a moment at most, for the ends to go through.
    static func endBeforeClosing() {
        let activities = Activity<RestActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        TraceLog.record(.timer, "Live Activity ended as PowerJack closes (\(activities.count))")
        let ended = DispatchSemaphore(value: 0)
        Task.detached {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            ended.signal()
        }
        _ = ended.wait(timeout: .now() + 2)
    }

    private static func end(_ activities: [Activity<RestActivityAttributes>]) async {
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
