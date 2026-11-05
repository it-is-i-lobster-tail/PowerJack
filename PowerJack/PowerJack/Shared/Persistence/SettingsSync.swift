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
        Logger.sync.debug("Applied settings from iPhone")
    }
}
