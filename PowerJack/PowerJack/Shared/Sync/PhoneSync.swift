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
        guard let context else {
            TraceLog.record(.watch, "Dropped the watch's changes while iCloud Backup switches stores")
            return nil
        }
        do {
            let changes = try SyncPayload.decode([WatchChange].self, from: data)
            TraceLog.record(.watch, "Received \(changes.count) changes from the watch")
            let snapshot = try referee.receive(changes, in: context)
            // A set logged on the watch starts a rest, often with the iPhone locked and PowerJack's
            // screens not running to notice, so the voice and the Live Activity follow it here.
            let program = (try? context.fetch(FetchDescriptor<Program>()))?.active
            RestVoice.shared.follow(program?.nextWorkout)
            Task { await RestLiveActivityController.follow(program) }
            return try SyncPayload.encode(snapshot)
        } catch {
            Logger.sync.error("Could not apply the watch's changes: \(error.localizedDescription)")
            TraceLog.record(.watch, "Could not apply the watch's changes: \(TraceLog.describe(error))")
            return nil
        }
    }

    /// Waits for saves to settle, so a burst of edits sends the program once.
    private func scheduleSend() {
        scheduledSend?.cancel()
        scheduledSend = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.send()
        }
    }

    private func send() async {
        guard let context else { return }
        do {
            let snapshot = try SyncPayload.encode(try referee.snapshot(in: context))
            let delivery = DeviceLink.shared.send(snapshot: snapshot)
            let mirrored = await WorkoutMirroring.shared.send(snapshot)
            TraceLog.record(.watch, "Program for the watch (\(snapshot.count) bytes): \(delivery.rawValue)\(mirrored ? ", mirrored" : "")")
        } catch {
            Logger.sync.error("Could not send the program to the watch: \(error.localizedDescription)")
            TraceLog.record(.watch, "Could not send the program to the watch: \(TraceLog.describe(error))")
        }
    }
}
