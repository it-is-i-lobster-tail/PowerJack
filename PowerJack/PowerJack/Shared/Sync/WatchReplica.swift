//
//  WatchReplica.swift
//  PowerJack
//
//  The watch's side of the direct link with the iPhone. Every change the watch makes waits here
//  until the iPhone says it has it, and the watch only takes the iPhone's program once it does,
//  so nothing logged on the watch is ever overwritten before the iPhone has seen it.
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class WatchReplica {
    private enum Key {
        static let install = "sync.install"
        static let lastChangeID = "sync.lastChangeID"
        static let pending = "sync.pendingChanges"
        static let running = "sync.runningOnIPhone"
        static let heard = "sync.heardFromIPhone"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Names this install of the watch app, so the iPhone counts its changes apart from another's.
    var install: UUID {
        if let saved = defaults.string(forKey: Key.install).flatMap(UUID.init(uuidString:)) { return saved }
        let install = UUID()
        defaults.set(install.uuidString, forKey: Key.install)
        return install
    }

    /// Changes the iPhone doesn't have yet, oldest first.
    private(set) var pending: [WatchChange] {
        get {
            guard let data = defaults.data(forKey: Key.pending) else { return [] }
            return (try? JSONDecoder().decode([WatchChange].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.pending) }
    }

    /// The program the iPhone last said is running.
    private(set) var runningOnIPhone: UUID? {
        get { defaults.string(forKey: Key.running).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.running) }
    }

    /// Whether the iPhone has ever sent its program, so the watch can tell "waiting for the iPhone"
    /// apart from "nothing running on it".
    private(set) var heardFromIPhone: Bool {
        get { defaults.bool(forKey: Key.heard) }
        set { defaults.set(newValue, forKey: Key.heard) }
    }

    /// Keeps a change made on the watch until the iPhone has it.
    @discardableResult
    func record(_ action: WatchChange.Action, at row: RowPath?, together: Bool, date: Date = .now) -> WatchChange? {
        guard let row else {
            Logger.sync.warning("A watch change has no row to name")
            return nil
        }
        let id = defaults.integer(forKey: Key.lastChangeID) + 1
        defaults.set(id, forKey: Key.lastChangeID)
        let change = WatchChange(id: id, install: install, date: date, together: together, row: row, action: action)
        pending.append(change)
        return change
    }

    /// Takes the iPhone's program once it holds every change the watch made. Until then the watch keeps
    /// its own and sends what's pending again.
    /// - Returns: Whether the program was applied.
    @discardableResult
    func receive(_ snapshot: ProgramSnapshot, in context: ModelContext) throws -> Bool {
        heardFromIPhone = true
        let applied = snapshot.applied[install.uuidString] ?? 0
        pending.removeAll { $0.id <= applied }
        guard pending.isEmpty else { return false }
        try snapshot.apply(to: context)
        if let running = snapshot.program?.syncID {
            runningOnIPhone = running
        }
        try SyncTidyUp.run(in: context, running: runningOnIPhone)
        return true
    }
}
