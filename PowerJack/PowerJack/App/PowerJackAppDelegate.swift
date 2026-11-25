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
import UserNotifications

final class PowerJackAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        WorkoutReminders.shared.registerCategory()
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier == WorkoutReminders.category,
              [UNNotificationDefaultActionIdentifier, WorkoutReminders.previewAction].contains(response.actionIdentifier),
              let id = content.userInfo[WorkoutReminders.workoutIDKey] as? String,
              let workoutID = UUID(uuidString: id) else { return }
        let highlight = content.userInfo[WorkoutReminders.highlightKey] as? Data
        await WorkoutReminders.shared.open(workoutID: workoutID, highlightData: highlight)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.categoryIdentifier == WorkoutReminders.category ? [.banner, .list, .sound] : []
    }

    func applicationWillTerminate(_ application: UIApplication) {
        WorkoutMirroring.shared.endWatchWorkout()
        RestLiveActivityController.endBeforeClosing()
    }
}
