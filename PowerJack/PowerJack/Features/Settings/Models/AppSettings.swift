//
//  AppSettings.swift
//  PowerJack
//
//  UserDefaults keys and defaults behind the Settings screen.
//  Read them with `@AppStorage(AppSettings.Key.x) var x = AppSettings.Default.x`.
//

enum AppSettings {
    enum Key {
        static let inAppRestTimer = "settings.restTimer.inApp"
        static let restLiveActivity = "settings.restTimer.liveActivity"
        static let restVoice = "settings.restTimer.voice"
        static let hapticsOnPhone = "settings.restTimer.hapticsOnPhone"
        static let hapticsOnWatch = "settings.restTimer.hapticsOnWatch"
        static let headsUp = "settings.restTimer.headsUp"
        static let headsUpLead = "settings.restTimer.headsUpLead"
        static let headsUpPattern = "settings.restTimer.headsUpPattern"
        static let liftPattern = "settings.restTimer.liftPattern"
        static let iCloudBackup = "settings.iCloudBackup"
        static let hints = "settings.hints"
        static let weightUnit = "settings.weightUnit"
        static let appearance = "settings.appearance"
    }

    enum Default {
        static let inAppRestTimer = true
        static let restLiveActivity = true
        static let restVoice = false
        static let hapticsOnPhone = true
        static let hapticsOnWatch = true
        static let headsUp = true
        /// Seconds before the rest ends.
        static let headsUpLead = 15
        static let headsUpPattern = HapticPattern.oneShort
        static let liftPattern = HapticPattern.shortShortLong
        static let iCloudBackup = true
        static let hints = true
    }
}
