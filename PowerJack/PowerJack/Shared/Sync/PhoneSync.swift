//
//  PhoneSync.swift
//  PowerJack
//
//  Keeps the watch in step with the iPhone, straight over `DeviceLink` and `WorkoutMirroring`:
//  it answers the watch's changes with the program, and sends the program again whenever it's saved.
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class PhoneSync {
    static let shared = PhoneSync()

    private let referee = PhoneReferee()
    private weak var store: PowerJackStore?
    private var scheduledSend: Task<Void, Never>?

    func start(store: PowerJackStore) {
        self.store = store
        DeviceLink.shared.onChanges = { [weak self] in self?.receive(changes: $0) }
        WorkoutMirroring.shared.onData = { [weak self] in self?.receive(changes: $0) }
        WorkoutMirroring.shared.start()
        DeviceLink.shared.start()
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                self?.scheduleSend()
            }
        }
        scheduleSend()
    }

    /// Nil while iCloud Backup switches stores, when no model may be read.
    private var context: ModelContext? {
        guard let store, !store.isReplacingContainer else { return nil }
        return store.container.mainContext
    }

    private func receive(changes data: Data) -> Data? {
        guard let context else { return nil }
        do {
            let changes = try SyncPayload.decode([WatchChange].self, from: data)
            return try SyncPayload.encode(try referee.receive(changes, in: context))
        } catch {
            Logger.sync.error("Could not apply the watch's changes: \(error.localizedDescription)")
            return nil
        }
    }

    /// Waits for saves to settle, so a burst of edits sends the program once.
    private func scheduleSend() {
        scheduledSend?.cancel()
        scheduledSend = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.send()
        }
    }

    private func send() async {
        guard let context else { return }
        do {
            let snapshot = try SyncPayload.encode(try referee.snapshot(in: context))
            DeviceLink.shared.send(snapshot: snapshot)
            _ = await WorkoutMirroring.shared.send(snapshot)
        } catch {
            Logger.sync.error("Could not send the program to the watch: \(error.localizedDescription)")
        }
    }
}
