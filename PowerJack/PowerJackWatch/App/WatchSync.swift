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

    /// Whether the iPhone has sent its program yet. Until then an empty watch is waiting for it,
    /// not showing that nothing runs.
    private(set) var heardFromIPhone: Bool

    init(store: WatchStore) {
        self.store = store
        heardFromIPhone = replica.heardFromIPhone
        DeviceLink.shared.onSnapshot = { [weak self] in self?.receive(snapshot: $0) }
        // Opening the app asks before the link is up, so ask again once it is, and whenever the iPhone comes back.
        DeviceLink.shared.onConnected = { [weak self] in self?.push() }
        WorkoutMirroring.shared.onData = { [weak self] in self?.receive(snapshot: $0) }
        DeviceLink.shared.start()
    }

    /// Does what a screen did to the workout, saves it and sends it to the iPhone.
    func perform(_ change: (WatchActions) -> Void) {
        let together = DeviceLink.shared.isReachable || WorkoutMirroring.shared.isMirroring
        change(WatchActions(replica: replica, together: together))
        do {
            try store.container.mainContext.save()
        } catch {
            Logger.sync.error("Could not save the watch's change: \(error.localizedDescription)")
        }
        push()
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

    private func hasWorkoutInProgress(in context: ModelContext) throws -> Bool {
        try context.fetch(FetchDescriptor<Program>()).active?.nextWorkout?.status == .active
    }

    private func receive(snapshot data: Data) {
        do {
            let snapshot = try SyncPayload.decode(ProgramSnapshot.self, from: data)
            defer { heardFromIPhone = replica.heardFromIPhone }
            let context = store.container.mainContext
            let wasTraining = try hasWorkoutInProgress(in: context)
            guard try replica.receive(snapshot, in: context) else {
                // The iPhone doesn't have every change yet: send them before taking its program.
                push()
                return
            }
            // A workout finished on the iPhone ends the watch's session too, so the watch stops holding the screen.
            if wasTraining, try !hasWorkoutInProgress(in: context) {
                WorkoutMirroring.shared.end()
            }
        } catch {
            Logger.sync.error("Could not apply the iPhone's program: \(error.localizedDescription)")
        }
    }
}
