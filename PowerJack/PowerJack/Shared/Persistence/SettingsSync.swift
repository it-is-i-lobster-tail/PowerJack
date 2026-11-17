//
//  SettingsSync.swift
//  PowerJack
//
//  The iPhone's settings, which go to the watch so it shows the same unit and rests and plans
//  next week with the same load steps. Settings are only changed on the iPhone. `DeviceLink`
//  carries them.
//

import Foundation
import OSLog

final class SettingsSync {
    /// Every setting is stored under this prefix (see `AppSettings`).
    static let keyPrefix = "settings."
    /// Set on the watch once the iPhone's settings have arrived. Outside the prefix, so `apply` keeps it.
    private static let receivedKey = "sync.receivedSettings"

    /// The watch follows the iPhone's iCloud Backup setting. It stays off until the iPhone's settings
    /// arrive once, so a new watch never syncs through iCloud while the iPhone has backup off.
    /// A watch that already had a program from the iPhone got its settings along with it.
    static func watchSyncsWithICloud(in defaults: UserDefaults = .standard) -> Bool {
        if let saved = defaults.object(forKey: AppSettings.Key.iCloudBackup) as? Bool { return saved }
        let heardFromIPhone = defaults.bool(forKey: receivedKey) || WatchReplica(defaults: defaults).heardFromIPhone
        return heardFromIPhone && AppSettings.Default.iCloudBackup
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The settings as stored on this device.
    var settings: [String: Any] {
        defaults.dictionaryRepresentation().filter { $0.key.hasPrefix(Self.keyPrefix) }
    }

    /// Makes this device's settings match `received`. A setting the iPhone no longer has goes back to its default.
    func apply(_ received: [String: Any]) {
        for key in settings.keys where received[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in received where key.hasPrefix(Self.keyPrefix) {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: Self.receivedKey)
        Logger.sync.debug("Applied settings from iPhone")
    }
}

extension SettingsSync {
    /// Posted on the main thread when a setting changes. Other writes to UserDefaults, which happen
    /// all the time, don't post it.
    static let didChange = Notification.Name("PowerJack.SettingsSync.didChange")

    private static var observer: NSObjectProtocol?
    private static var lastSettings: NSDictionary = [:]

    /// Starts posting `didChange`. The settings are read once for each UserDefaults change, however
    /// many parts of the app follow them.
    static func startWatching(_ defaults: UserDefaults = .standard) {
        guard observer == nil else { return }
        lastSettings = NSDictionary(dictionary: SettingsSync(defaults: defaults).settings)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let settings = NSDictionary(dictionary: SettingsSync(defaults: defaults).settings)
                guard settings != lastSettings else { return }
                lastSettings = settings
                NotificationCenter.default.post(name: didChange, object: nil)
            }
        }
    }
}
