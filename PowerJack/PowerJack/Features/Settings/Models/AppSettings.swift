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
        static let iCloudBackup = "settings.iCloudBackup"
    }

    enum Default {
        static let inAppRestTimer = true
        static let restLiveActivity = true
        static let iCloudBackup = true
    }
}
