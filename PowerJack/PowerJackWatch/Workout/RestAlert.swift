//
//  RestAlert.swift
//  PowerJackWatch
//
//  Taps the wrist when a rest is over: a haptic while PowerJack is on screen,
//  a notification once the wrist is down.
//

import OSLog
import UserNotifications
import WatchKit

enum RestAlert {
    private static let identifier = "rest"

    /// Replaces any pending alert with one for `rest`, then waits for it to end on screen.
    /// Cancelled when the rest changes, so only the latest rest ever taps.
    static func schedule(for rest: RestPeriod?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let rest, rest.isResting(at: .now) else { return }

        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Rest's up"
            content.body = "\(rest.exerciseName) · \(rest.detailText)"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: rest.remaining(at: .now), repeats: false)
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        } catch {
            Logger.ui.error("Could not schedule the rest alert: \(error.localizedDescription)")
        }

        // On screen the notification isn't shown, so tap here instead.
        try? await Task.sleep(for: .seconds(rest.remaining(at: .now)))
        guard !Task.isCancelled else { return }
        WKInterfaceDevice.current().play(.stop)
    }
}
