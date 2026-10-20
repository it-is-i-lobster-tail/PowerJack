//
//  ProgramWeek.swift
//  PowerJack
//
//  Created by Brendon on 6/29/26.
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

    init(order: Int) {
        self.orderValue = order
        self.workoutsValue = []
        self.lockedValue = false
        self.statusValue = .planned
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
