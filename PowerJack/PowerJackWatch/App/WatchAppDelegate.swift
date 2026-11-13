//
//  WatchAppDelegate.swift
//  PowerJackWatch
//
//  Starting a workout on the iPhone opens PowerJack on the watch, the way Apple's Workout app
//  does: the iPhone hands the watch a workout configuration, and the watch starts its workout
//  session right away, which keeps the app on screen until the workout ends.
//

import HealthKit
import Observation
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WorkoutLaunch.shared.opensActiveWorkout = true
        Task { await WorkoutMirroring.shared.begin() }
    }
}

/// Asks the home screen to open the workout in progress, once the watch has it.
@Observable
final class WorkoutLaunch {
    static let shared = WorkoutLaunch()

    /// Set when the iPhone starts a workout or its Live Activity is tapped; cleared once the workout is open.
    var opensActiveWorkout = false
}
