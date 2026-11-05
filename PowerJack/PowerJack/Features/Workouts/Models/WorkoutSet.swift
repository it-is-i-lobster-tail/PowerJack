//
//  WorkoutSet.swift
//  PowerJack
//
//  Created on 6/24/26.
//

import Foundation
import SwiftData
import OSLog

@Model
final class WorkoutSet {
    private var orderValue: Int = 0
    // Stored as the raw string: SwiftData fails to cast a stored `SetType` back on read.
    private var setTypeValue: String = SetType.working.rawValue
    private var repsValue: Int?
    private var repsPlannedValue: Int?
    private var weightTenthsPoundsValue: Int?
    private var weightTenthsPoundsPlannedValue: Int?
    private var statusValue: Status = Status.planned
    private var lockedValue: Bool = false
    // Starts the rest timer. Cleared when the set is reopened.
    private var completedAtValue: Date? = nil
    // When the set's clock started: the set logged before it anywhere in the workout, or the workout's start.
    private var startedAtValue: Date? = nil
    var workoutExerciseValue: WorkoutExercise?
    // The same on the iPhone and the watch (see `SyncState`). Nil on rows saved before it existed.
    var syncIDValue: UUID?
    // True when the watch made this row from the iPhone's snapshot.
    var fromSnapshotValue: Bool = false

    init(
        order: Int,
        setType: SetType = .working,
        plannedReps: Int?,
        plannedWeightTenthsPounds: Int?,
    ) {
        self.orderValue = order
        self.setTypeValue = setType.rawValue
        self.repsPlannedValue = plannedReps.flatMap { Self.isValidReps($0) ? $0 : nil }
        self.weightTenthsPoundsPlannedValue = plannedWeightTenthsPounds
        self.statusValue = .planned
        self.lockedValue = false
        self.syncIDValue = UUID()
    }
}

//
// Public Accessors
//
extension WorkoutSet {
    // Order
    var order: Int {
        get { orderValue }
        set { orderValue = newValue }
    }
    // Set Type
    var setType: SetType { SetType(rawValue: setTypeValue) ?? .working }
    var isWarmup: Bool { setType == .warmup }
    // Reps
    var reps: Int? {
        get { repsValue }
        set {
            guard status == .active else { return }

            if let newValue, Self.isValidReps(newValue) {
                repsValue = newValue
            } else {
                repsValue = nil
            }
        }
    }
    // Reps Planned
    var repsPlanned: Int? {
        get { repsPlannedValue }
        set {
            guard status == .active else { return }

            if let newValue, Self.isValidReps(newValue) {
                repsPlannedValue = newValue
            } else {
                repsPlannedValue = nil
            }
        }
    }
    // Weight
    var weightTenthsPounds: Int? {
        get { self.weightTenthsPoundsValue }
        set {
            guard status == .active else { return }

            if let newValue, Self.isValidWeightTenthsPounds(newValue) {
                weightTenthsPoundsValue = newValue
            } else {
                weightTenthsPoundsValue = nil
            }
        }
    }
    // Weight Planned
    var weightTenthsPlannedPounds: Int? {
        get { self.weightTenthsPoundsPlannedValue }
        set {
            guard status == .planned else { return }

            if let newValue, newValue > 0 {
                weightTenthsPoundsPlannedValue = newValue
            } else {
                weightTenthsPoundsPlannedValue = nil
            }
        }
    }
    // Status
    var status: Status { statusValue }
    // Locked
    var locked: Bool { lockedValue }
    // Completed At
    var completedAt: Date? { completedAtValue }
    // Started At
    var startedAt: Date? { startedAtValue }
}
//
// Derived Values
//
extension WorkoutSet {
    /// The most reps a set can log.
    static let maxReps = 50
    /// The heaviest weight a set can log, in pounds.
    static let maxWeightPounds = 1000

    /// Reps above `maxReps` can never be saved.
    static func isValidReps(_ reps: Int) -> Bool {
        (1...maxReps).contains(reps)
    }

    /// When the lifter logged their first set in any program, or nil before they've logged one.
    static func firstCompletedAt(in context: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.completedAtValue != nil },
            sortBy: [SortDescriptor(\.completedAtValue)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.completedAt
    }
    /// Weights above `maxWeightPounds` can never be logged.
    static func isValidWeightTenthsPounds(_ weightTenthsPounds: Int) -> Bool {
        (1...maxWeightPounds * 10).contains(weightTenthsPounds)
    }
    // Complete or skipped
    var isDone: Bool { status == .complete || status == .skipped }
    /// How long the set took, rest before it included. `nil` until it's logged.
    var duration: TimeInterval? {
        guard status == .complete, let startedAtValue, let completedAtValue else { return nil }
        return max(0, completedAtValue.timeIntervalSince(startedAtValue))
    }
    // Weight In Pounds
    var weightInPounds: Double? {
        get {
            guard let weightTenthsPoundsValue else { return nil }
            return Double(weightTenthsPoundsValue) / 10.0
        }
        set {
            guard status == .active else { return }
            if let newValue, newValue > 0 {
                weightTenthsPounds = Int((newValue * 10).rounded())
            } else {
                weightTenthsPounds = nil
            }
        }
    }
    // Weight Planned In Pound
    var weightInPoundsPlanned: Double? {
        get {
            guard let weightTenthsPoundsPlannedValue else { return nil }
            return Double(weightTenthsPoundsPlannedValue) / 10.0
        }
        set {
            guard status == .planned else { return }
            if let newValue, newValue > 0 {
                weightTenthsPlannedPounds = Int((newValue * 10).rounded())
            } else {
                weightTenthsPlannedPounds = nil
            }
        }
    }
}

//
// Mutations
//

extension WorkoutSet {
    func completeAndLock(at date: Date = .now) {
        guard
            !lockedValue,
            status == .active || status == .complete
        else {
            Logger.workoutSet.warning("Cannot complete a locked or skipped WorkoutSet")
            return
        }
        // An already completed set keeps the time it was actually done.
        if status != .complete {
            completedAtValue = date
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.workoutSet.debug("WorkoutSet Completed and locked")
    }
    func complete(at date: Date = .now, startedAt: Date? = nil) {
        guard
            !lockedValue,
            status == .active
        else {
            Logger.workoutSet.warning("Cannot complete a locked or skipped WorkoutSet")
            return
        }
        statusValue = Status.complete
        completedAtValue = date
        startedAtValue = startedAt
        Logger.workoutSet.debug("WorkoutSet Completed")
    }
    func skip() {
        guard
            !lockedValue,
            status == .planned || status == .active
        else {
            Logger.workoutSet.warning("Cannot skip a locked WorkoutSet.")
            return
        }
        statusValue = Status.skipped
        lockedValue = true
        Logger.workoutSet.debug("WorkoutSet skipped")
    }
    func stop() {
        skip()
    }
    /// Opens a skipped set again, keeping the reps and weight it was holding.
    func unskip() {
        guard status == .skipped else {
            Logger.workoutSet.warning("Can only unskip a skipped WorkoutSet.")
            return
        }
        statusValue = Status.active
        lockedValue = false
        Logger.workoutSet.debug("WorkoutSet unskipped")
    }
    /// Back to planned, as if its workout never started. The next start fills in the target again.
    func resetToPlanned() {
        statusValue = Status.planned
        lockedValue = false
        repsValue = nil
        weightTenthsPoundsValue = nil
        completedAtValue = nil
        startedAtValue = nil
        Logger.workoutSet.debug("WorkoutSet reset to planned")
    }
    func start() {
        guard
            !lockedValue
        else {
            Logger.workoutSet.warning("Can only start a WorkoutSet that is not locked.")
            return
        }

        let wasPlanned = status == .planned
        statusValue = Status.active
        completedAtValue = nil
        startedAtValue = nil
        // A set starts out holding its target, so the lifter only edits it when they go off plan.
        if wasPlanned {
            reps = reps ?? repsPlanned
            weightTenthsPounds = weightTenthsPounds ?? weightTenthsPlannedPounds
        }
        Logger.workoutSet.debug("Starting WorkoutSet")
    }
}

//
// Sync
//
extension WorkoutSet {
    var syncID: UUID? { syncIDValue }
    var isFromSnapshot: Bool { fromSnapshotValue }

    /// Gives a row saved before sync IDs existed its own. Only the iPhone does this, so both devices agree.
    func assignSyncID() {
        if syncIDValue == nil { syncIDValue = UUID() }
    }

    /// What this set holds when it's logged.
    var log: SetLog? {
        guard status == .complete, let completedAtValue else { return nil }
        return SetLog(weightTenthsPounds: weightTenthsPoundsValue, reps: repsValue, completedAt: completedAtValue)
    }

    var syncState: SetState? {
        guard let syncIDValue else { return nil }
        return SetState(
            syncID: syncIDValue,
            order: orderValue,
            setType: setTypeValue,
            reps: repsValue,
            repsPlanned: repsPlannedValue,
            weightTenthsPounds: weightTenthsPoundsValue,
            weightTenthsPoundsPlanned: weightTenthsPoundsPlannedValue,
            status: statusValue,
            locked: lockedValue,
            completedAt: completedAtValue,
            startedAt: startedAtValue
        )
    }

    /// A row the watch makes for a set it hasn't got yet.
    convenience init(snapshot state: SetState) {
        self.init(order: state.order, plannedReps: nil, plannedWeightTenthsPounds: nil)
        fromSnapshotValue = true
        apply(state)
    }

    /// Makes this set match the iPhone's copy of it.
    func apply(_ state: SetState) {
        syncIDValue = state.syncID
        orderValue = state.order
        setTypeValue = state.setType
        repsValue = state.reps
        repsPlannedValue = state.repsPlanned
        weightTenthsPoundsValue = state.weightTenthsPounds
        weightTenthsPoundsPlannedValue = state.weightTenthsPoundsPlanned
        statusValue = state.status
        lockedValue = state.locked
        completedAtValue = state.completedAt
        startedAtValue = state.startedAt
    }

    /// Takes over the other copy's log when it's newer: a logged set beats an unlogged one,
    /// and a later log an earlier one (apart, the latest log wins).
    func merge(_ other: WorkoutSet) {
        let otherIsNewer: Bool
        switch (log, other.log) {
        case (nil, .some): otherIsNewer = true
        case (.some(let mine), .some(let theirs)): otherIsNewer = theirs.completedAt > mine.completedAt
        case (nil, nil): otherIsNewer = other.status.progress > status.progress
        case (.some, nil): otherIsNewer = false
        }
        guard otherIsNewer else { return }
        repsValue = other.repsValue
        repsPlannedValue = other.repsPlannedValue
        weightTenthsPoundsValue = other.weightTenthsPoundsValue
        weightTenthsPoundsPlannedValue = other.weightTenthsPoundsPlannedValue
        statusValue = other.statusValue
        lockedValue = other.lockedValue
        completedAtValue = other.completedAtValue
        startedAtValue = other.startedAtValue
    }

    /// Shows `log` instead of what the set holds, when it was logged later. Rebuilds a set that an
    /// older upload overwrote. Only logged sets change: one that was reopened stays open.
    @discardableResult
    func showLatest(_ log: SetLog) -> Bool {
        guard let current = self.log, log.completedAt.timeIntervalSince(current.completedAt) > SetLog.sameMoment else { return false }
        repsValue = log.reps
        weightTenthsPoundsValue = log.weightTenthsPounds
        completedAtValue = log.completedAt
        return true
    }

    /// Settles a set both devices logged: it shows `log`, stamped at `date`, which is after both logs,
    /// so the receipts (latest log wins) agree with the referee.
    func restamp(_ log: SetLog, at date: Date) {
        guard status == .complete else { return }
        repsValue = log.reps
        weightTenthsPoundsValue = log.weightTenthsPounds
        completedAtValue = date
    }

    /// Logged sets whose log is at least as new as `date`.
    static func logged(since date: Date, in context: ModelContext) throws -> [WorkoutSet] {
        try context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { workoutSet in
            if let completedAt = workoutSet.completedAtValue { completedAt >= date } else { false }
        }))
    }

    static func fromSnapshot(in context: ModelContext) throws -> [WorkoutSet] {
        try context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.fromSnapshotValue }))
    }
}
