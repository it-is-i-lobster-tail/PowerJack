//
//  DeviceLink.swift
//  PowerJack
//
//  The direct link between the iPhone and the watch, over WatchConnectivity. It carries the
//  iPhone's settings and running program to the watch, and the watch's changes to the iPhone.
//  It works without iCloud, so the watch trains with iCloud Backup off as long as the iPhone
//  is nearby now and then. During a workout `WorkoutMirroring` carries the same data faster.
//

import Foundation
import OSLog
import WatchConnectivity

final class DeviceLink: NSObject {
    static let shared = DeviceLink()

    private nonisolated enum Key {
        static let snapshot = "sync.snapshot"
        static let changes = "sync.changes"
    }

    private let settingsSync = SettingsSync()
    private var observer: NSObjectProtocol?

    #if os(iOS)
    /// Applies changes from the watch and answers with the program. Set by `PhoneSync`.
    var onChanges: ((Data) -> Data?)?
    private var lastContext: [String: Any] = [:]
    private var latestSnapshot: Data?
    #else
    /// Takes the program the iPhone sent. Set by `WatchSync`.
    var onSnapshot: ((Data) -> Void)?
    #endif

    func start() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        #if os(iOS)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateContext() }
        }
        #endif
    }

    /// Whether the other device can be reached right now.
    var isReachable: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    #if os(iOS)
    /// Sends the program now when the watch app is reachable, and leaves it for the watch's next launch.
    func send(snapshot: Data) {
        latestSnapshot = snapshot
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        if session.isReachable {
            session.sendMessage([Key.snapshot: snapshot], replyHandler: nil) { error in
                Logger.sync.debug("Could not send the program to the watch now: \(error.localizedDescription)")
            }
        }
        updateContext()
    }

    /// The watch reads the latest settings and program when it next runs. A program too big for that
    /// goes as a file instead.
    private func updateContext() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        var context = settingsSync.settings
        context[Key.snapshot] = latestSnapshot
        guard !NSDictionary(dictionary: context).isEqual(to: lastContext) else { return }
        do {
            try session.updateApplicationContext(context)
            lastContext = context
        } catch WCError.payloadTooLarge {
            context[Key.snapshot] = nil
            try? session.updateApplicationContext(context)
            lastContext = context
            sendFile(latestSnapshot)
        } catch {
            Logger.sync.error("Could not update what the watch reads: \(error.localizedDescription)")
        }
    }

    private func sendFile(_ snapshot: Data?) {
        guard let snapshot else { return }
        let url = URL.temporaryDirectory.appending(path: "program-\(UUID().uuidString).snapshot")
        do {
            try snapshot.write(to: url)
            for transfer in WCSession.default.outstandingFileTransfers { transfer.cancel() }
            WCSession.default.transferFile(url, metadata: nil)
        } catch {
            Logger.sync.error("Could not send the program to the watch: \(error.localizedDescription)")
        }
    }

    private func received(changes data: Data) -> Data? {
        onChanges?(data)
    }
    #else
    /// Sends everything pending. When the iPhone answers straight away its program comes back;
    /// otherwise the changes wait in the queue until it can be reached.
    func send(changes: Data) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isReachable else {
            queue(changes)
            return
        }
        session.sendMessage([Key.changes: changes]) { [weak self] reply in
            guard let snapshot = reply[Key.snapshot] as? Data else { return }
            Task { @MainActor in self?.onSnapshot?(snapshot) }
        } errorHandler: { [weak self] error in
            Logger.sync.debug("Could not reach the iPhone now: \(error.localizedDescription)")
            Task { @MainActor in self?.queue(changes) }
        }
    }

    /// Each send holds every pending change, so only the newest needs to wait.
    private func queue(_ changes: Data) {
        for transfer in WCSession.default.outstandingUserInfoTransfers { transfer.cancel() }
        WCSession.default.transferUserInfo([Key.changes: changes])
    }

    private func received(context: [String: Any]) {
        settingsSync.apply(context)
        if let snapshot = context[Key.snapshot] as? Data {
            onSnapshot?(snapshot)
        }
    }
    #endif
}

extension DeviceLink: WCSessionDelegate {
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
            self.updateContext()
            #else
            if !received.isEmpty { self.received(context: received) }
            #endif
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        nonisolated(unsafe) let message = message
        Task { @MainActor in self.received(message: message, reply: nil) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        nonisolated(unsafe) let message = message
        nonisolated(unsafe) let replyHandler = replyHandler
        Task { @MainActor in self.received(message: message, reply: replyHandler) }
    }

    @MainActor
    private func received(message: [String: Any], reply: (([String: Any]) -> Void)?) {
        #if os(iOS)
        let answer = (message[Key.changes] as? Data).flatMap(received(changes:))
        reply?(answer.map { [Key.snapshot: $0] } ?? [:])
        #else
        if let snapshot = message[Key.snapshot] as? Data {
            onSnapshot?(snapshot)
        }
        reply?([:])
        #endif
    }

    #if os(iOS)
    /// Changes the watch queued while the iPhone couldn't be reached.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let changes = userInfo[Key.changes] as? Data else { return }
        Task { @MainActor in
            if let answer = self.received(changes: changes) {
                self.send(snapshot: answer)
            }
        }
    }

    /// The watch app was just installed, or a watch was paired. Catch it up.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastContext = [:]
            self.updateContext()
        }
    }

    /// The watch app came to the front or back in range: give it the latest program now, since one
    /// sent while it was away only waits in the application context.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            if let latestSnapshot = self.latestSnapshot { self.send(snapshot: latestSnapshot) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another watch. Start again so it gets the settings and program too.
        session.activate()
    }
    #else
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        nonisolated(unsafe) let received = applicationContext
        Task { @MainActor in self.received(context: received) }
    }

    /// A program too big for the application context.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let snapshot = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in self.onSnapshot?(snapshot) }
    }
    #endif
}

/// What crosses the link: JSON, compressed, since a whole program repeats itself a lot.
enum SyncPayload {
    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        try (JSONEncoder().encode(value) as NSData).compressed(using: .lzfse) as Data
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: (data as NSData).decompressed(using: .lzfse) as Data)
    }
}
