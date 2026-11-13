//
//  WatchSync.swift
//  PowerJackWatch
//
//  The watch's side of the direct link with the iPhone. Every change a screen makes is sent
//  straight away, over the workout session while one runs and over `DeviceLink` otherwise, and
//  waits in `WatchReplica` until the iPhone has it. Works with iCloud Backup off.
//

import Foundation
import Observation
import OSLog
import SwiftData

@MainActor
@Observable
final class WatchSync {
    @ObservationIgnored private let replica = WatchReplica()
    @ObservationIgnored private let store: WatchStore

    init(store: WatchStore) {
        self.store = store
        DeviceLink.shared.onSnapshot = { [weak self] in self?.receive(snapshot: $0) }
        WorkoutMirroring.shared.onData = { [weak self] in self?.receive(snapshot: $0) }
        DeviceLink.shared.start()
    }

    /// Does what a screen did to the workout, saves it and sends it to the iPhone.
    func perform(_ change: (WatchActions) -> Void) {
        scheduledSend?.cancel()
        change(WatchActions(replica: replica, together: isTogether))
        saveAndPush()
    }

    /// Sends everything pending. With nothing pending it just asks the iPhone for its program.
    func push() {
        guard let changes = try? SyncPayload.encode(replica.pending) else { return }
        Task {
            if await !WorkoutMirroring.shared.send(changes) {
                DeviceLink.shared.send(changes: changes)
            }
        }
    }

    private func receive(snapshot data: Data) {
        do {
            let snapshot = try SyncPayload.decode(ProgramSnapshot.self, from: data)
            if try !replica.receive(snapshot, in: store.container.mainContext) {
                // The iPhone doesn't have every change yet: send them before taking its program.
                push()
            }
        } catch {
            Logger.sync.error("Could not apply the iPhone's program: \(error.localizedDescription)")
        }
    }

    @ObservationIgnored private var scheduledSend: Task<Void, Never>?

    private var isTogether: Bool {
        DeviceLink.shared.isReachable || WorkoutMirroring.shared.isMirroring
    }

    /// Like `perform`, for a change made many times a second, such as turning the Digital Crown:
    /// the screen shows it at once, and it's saved and sent once the crown rests for a moment.
    func performSoon(_ change: (WatchActions) -> Void) {
        change(WatchActions(replica: replica, together: isTogether))
        scheduledSend?.cancel()
        scheduledSend = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveAndPush()
        }
    }

    private func saveAndPush() {
        do {
            try store.container.mainContext.save()
        } catch {
            Logger.sync.error("Could not save the watch's change: \(error.localizedDescription)")
        }
        push()
    }
}
