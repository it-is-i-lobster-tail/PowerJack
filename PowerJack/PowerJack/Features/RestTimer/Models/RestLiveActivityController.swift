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
            await end(running)
            return
        }

        let attributes = RestActivityAttributes(workoutTitle: workoutTitle)
        // Past the stale date the widget swaps the countdown for "Start set".
        let content = ActivityContent(state: state, staleDate: state.rest?.upperBound)

        if let activity = running.first(where: { $0.attributes == attributes }) {
            await end(running.filter { $0.id != activity.id })
            if activity.content.state != state {
                await activity.update(content)
            }
            return
        }

        await end(running)
        do {
            _ = try Activity.request(attributes: attributes, content: content)
        } catch {
            Logger.restTimer.error("Could not start the workout Live Activity: \(error.localizedDescription)")
        }
    }

    private static func end(_ activities: [Activity<RestActivityAttributes>]) async {
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
