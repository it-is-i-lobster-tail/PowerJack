//
//  RestAlert.swift
//  PowerJackWatch
//
//  Taps the wrist as a rest ends: the rest cues in the patterns picked on the iPhone while
//  PowerJack is on screen, and a notification for each cue once the wrist is down.
//

import OSLog
import UserNotifications
import WatchKit

enum RestAlert {

    /// Replaces any pending alerts with ones for `rest`, then plays its cues on screen.
    /// Cancelled when the rest changes, so only the latest rest ever taps.
    static func schedule(for rest: RestPeriod?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: .headsUp), identifier(for: .lift)])
        guard let rest, rest.isResting(at: .now) else { return }

        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
            let settings = RestHapticSettings.current
            for (cue, date) in rest.cues(after: .now, settings: settings) {
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
                try await center.add(UNNotificationRequest(
                    identifier: identifier(for: cue),
                    content: content(for: cue, of: rest, settings: settings),
                    trigger: trigger
                ))
            }
        } catch {
            Logger.ui.error("Could not schedule the rest alert: \(error.localizedDescription)")
        }

        // On screen the notification isn't shown, so buzz here instead.
        await rest.playCues(play)
    }

    private static func identifier(for cue: RestCue) -> String {
        cue == .lift ? "rest" : "rest.headsUp"
    }

    /// Once the wrist is down, the notification's own tap stands in for the pattern.
    private static func content(for cue: RestCue, of rest: RestPeriod, settings: RestHapticSettings) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        switch cue {
        case .headsUp:
            content.title = "Get set"
            content.body = "\(settings.headsUpLead) sec left · \(rest.exerciseName)"
        case .lift:
            content.title = "Rest's up"
            content.body = "\(rest.exerciseName) · \(rest.detailText)"
        }
        content.sound = .default
        return content
    }

    /// watchOS has no custom haptics, so a strong tap stands in for a short buzz and the "start" haptic for a long one.
    private static func play(_ pattern: HapticPattern) async {
        for (index, isLong) in pattern.buzzes.enumerated() {
            if index > 0 {
                // Haptics played closer together than this run into each other.
                try? await Task.sleep(for: .seconds(0.4))
            }
            WKInterfaceDevice.current().play(isLong ? .start : .notification)
        }
    }
}
