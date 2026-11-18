//
//  PowerJackAppDelegate.swift
//  PowerJack
//
//  Closing PowerJack, such as swiping it away in the app switcher, ends its Live Activity and the
//  watch's workout session, so nothing keeps showing a workout running. The workout itself stays in
//  progress, and both come back once PowerJack is opened and the workout carries on.
//
//  iOS only says it is closing an app that is still running. One it has already suspended in the
//  background is closed without a word; its Live Activity then stays until PowerJack next opens,
//  which brings it in line with the workout again.
//

import UIKit

final class PowerJackAppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        WorkoutMirroring.shared.endWatchWorkout()
        RestLiveActivityController.endBeforeClosing()
    }
}
