//
//  SettingsSync.swift
//  PowerJack
//
//  Sends the iPhone's settings to the watch, so the watch shows the same unit and rests and
//  plans next week with the same load steps. Settings are only changed on the iPhone.
//  They go straight between the paired devices; workouts sync through iCloud instead.
//

import Foundation
import OSLog
import WatchConnectivity

final class SettingsSync: NSObject {
    static let shared = SettingsSync()

    /// Every setting is stored under this prefix (see `AppSettings`).
    static let keyPrefix = "settings."

    private let defaults: UserDefaults
    private var lastSent: [String: Any] = [:]
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        #if os(iOS)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.send() }
        }
        #endif
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

    #if os(iOS)
    private func send() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let current = settings
        guard !NSDictionary(dictionary: current).isEqual(to: lastSent) else { return }
        do {
            try session.updateApplicationContext(current)
            lastSent = current
        } catch {
            Logger.sync.error("Could not send settings to the watch: \(error.localizedDescription)")
        }
    }
    #endif
}

extension SettingsSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let failure = error?.localizedDescription
        #if !os(iOS)
        nonisolated(unsafe) let received = session.receivedApplicationContext
        #endif
        Task { @MainActor in
            if let failure {
                Logger.sync.error("Watch connection didn't start: \(failure)")
            }
            #if os(iOS)
            self.send()
            #else
            if !received.isEmpty { self.apply(received) }
            #endif
        }
    }

    #if os(iOS)
    /// The watch app was just installed, or a watch was paired. Catch it up.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastSent = [:]
            self.send()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another watch. Start again so it gets the settings too.
        session.activate()
    }
    #else
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        nonisolated(unsafe) let received = applicationContext
        Task { @MainActor in self.apply(received) }
    }
    #endif
}
