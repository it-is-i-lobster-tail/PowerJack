//
//  ProgramWeek.swift
//  PowerJack
//
//  Created on 6/29/26.
//

import Foundation
import SwiftData
import OSLog

@Model
final class ProgramWeek {
    var orderValue: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \Workout.programWeekValue)
    var workoutsValue: [Workout]? = []
    var lockedValue: Bool = false
    var statusValue: Status = Status.planned
    var programValue: Program?
    // Where the week sits in its training block. Empty and 0 for programs that don't use blocks.
    var weekKindValue: String = ""
    var blockWeekValue: Int = 0
    // The break band (1-3) when a long break was handled in this week, else 0.
    var returnBandValue: Int = 0
    // The same on the iPhone and the watch (see `SyncState`). Nil on rows saved before it existed.
    var syncIDValue: UUID?
    // True when the watch made this row from the iPhone's snapshot.
    var fromSnapshotValue: Bool = false

    init(order: Int) {
        self.orderValue = order
        self.workoutsValue = []
        self.lockedValue = false
        self.statusValue = .planned
        self.syncIDValue = UUID()
    }
}

//
// Public Accessors
//
extension ProgramWeek {
    // Order
    var order: Int { orderValue }
    // Workouts
    var workouts: [Workout] { (workoutsValue ?? []).sorted(byOrder: \.order) }
    // Lock
    var locked: Bool { self.lockedValue }
    // Status
    var status: Status { statusValue }
    // Block
    var weekKind: WeekKind? { WeekKind(rawValue: weekKindValue) }
    var blockWeek: Int { blockWeekValue }
    var returnBand: Int { returnBandValue }
}

//
// Mutations
//
extension ProgramWeek {
    func addWorkout() -> Workout? {
        guard !lockedValue else {
            Logger.programWeek.debug("Cannot add a Workout to a locked ProgramWeek")
            return nil
        }
        Logger.programWeek.debug("Adding Workout to ProgramWeek")
        let newWorkout = Workout(
            order: workouts.count
        )
        workoutsValue = (workoutsValue ?? []) + [newWorkout]
        return newWorkout
    }

    /// Places the week in its training block. Planners set this when they write the week.
    func setBlock(kind: WeekKind, blockWeek: Int, returnBand: Int = 0) {
        weekKindValue = kind.rawValue
        blockWeekValue = blockWeek
        returnBandValue = returnBand
    }

    /// Takes the week out of any training block, for planners that don't use them.
    func clearBlock() {
        weekKindValue = ""
        blockWeekValue = 0
        returnBandValue = 0
    }

    func complete() {
        guard !lockedValue else {
            Logger.programWeek.warning("Cannot complete a locked ProgramWeek.")
            return
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.programWeek.debug("Completed ProgramWeek")
    }
    func stop() {
        guard !lockedValue else {
            Logger.programWeek.warning("Cannot stop a locked ProgramWeek.")
            return
        }
        statusValue = Status.stopped
        lockedValue = true
        Logger.programWeek.debug("Stopped ProgramWeek")
    }
    func skip() {
        guard !lockedValue else {
            Logger.programWeek.warning("Cannot skip a locked ProgramWeek.")
            return
        }
        statusValue = Status.skipped
        lockedValue = true
        Logger.programWeek.debug("Skipped ProgramWeek")
    }
    func start() {
        guard
            !lockedValue,
            status == .planned
        else {
            Logger.programWeek.warning("Cannot start a locked or non-planned ProgramWeek.")
            return
        }
        statusValue = Status.active
        Logger.programWeek.debug("Started ProgramWeek")
    }
    func completeAndCascade() {
        complete()
        for workout in workouts {
            workout.completeAndCascade()
        }
    }
    func stopAndCascade() {
        stop()
        for workout in workouts {
            workout.stopAndCascade()
        }
    }
    func skipAndCascade() {
        skip()
        for workout in workouts {
            workout.skipAndCascade()
        }
    }
    func startAndCascade() {
        start()

        for workout in workouts {
            workout.startAndCascade()
        }
    }
}

//
// Sync
//
extension ProgramWeek {
    var syncID: UUID? { syncIDValue }
    var isFromSnapshot: Bool { fromSnapshotValue }

    /// Gives this row and everything under it sync IDs, for rows saved before they existed. Only the iPhone does this.
    func assignSyncIDs() {
        if syncIDValue == nil { syncIDValue = UUID() }
        for workout in workouts {
            workout.assignSyncIDs()
        }
    }

    var syncState: WeekState? {
        guard let syncIDValue else { return nil }
        return WeekState(
            syncID: syncIDValue,
            order: orderValue,
            status: statusValue,
            locked: lockedValue,
            weekKind: weekKindValue,
            blockWeek: blockWeekValue,
            returnBand: returnBandValue,
            workouts: workouts.compactMap(\.syncState)
        )
    }

    /// A row the watch makes for a week it hasn't got yet.
    convenience init(snapshot state: WeekState) {
        self.init(order: state.order)
        fromSnapshotValue = true
    }

    /// Makes this row match the iPhone's copy of it. Workouts are matched by the caller.
    func apply(_ state: WeekState) {
        syncIDValue = state.syncID
        orderValue = state.order
        statusValue = state.status
        lockedValue = state.locked
        weekKindValue = state.weekKind
        blockWeekValue = state.blockWeek
        returnBandValue = state.returnBand
    }

    func attach(_ workout: Workout) {
        workoutsValue = (workoutsValue ?? []) + [workout]
    }

    func detach(_ workout: Workout) {
        workoutsValue?.removeAll { $0 === workout }
    }

    /// Folds another copy of this week into it: its workouts merge or move over. A week only moves on
    /// through its program, so this copy's status stays unless the other one got further.
    func merge(_ other: ProgramWeek) {
        if other.statusValue.progress > statusValue.progress {
            statusValue = other.statusValue
            lockedValue = other.lockedValue
        }
        SyncMerge.fold(
            other.workouts,
            into: workouts,
            key: { $0.syncID.map(AnyHashable.init) },
            merge: { $0.merge($1, matching: .syncID) },
            move: { other.detach($0); self.attach($0) }
        )
    }

    static func fromSnapshot(in context: ModelContext) throws -> [ProgramWeek] {
        try context.fetch(FetchDescriptor<ProgramWeek>(predicate: #Predicate { $0.fromSnapshotValue }))
    }
}
