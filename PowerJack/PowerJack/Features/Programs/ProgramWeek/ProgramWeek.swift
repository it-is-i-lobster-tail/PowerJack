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
final class ProgramWeek{
    var orderValue: Int
    var workoutsValue: [Workout]
    var lockedValue: Bool
    var statusValue: Status
    
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
    var workouts: [Workout] { workoutsValue.sorted {$0.order < $1.order} }
    // Lock
    var locked: Bool { self.lockedValue }
    // Status
    var status: Status { statusValue }
}

//
// Mutations
//
extension ProgramWeek {
    func addWorkout() -> Workout? {
        guard lockedValue else {
            Logger.programWeek.debug("Cannot add new Workout to locked ProgramWeek")
            return nil
        }
        Logger.programWeek.debug("Adding Workout to ProgramWeek")
        let newWorkout = Workout(
            order: workoutsValue.count
        )
        workoutsValue.append(newWorkout)
        return newWorkout
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
            lockedValue
        else {
            Logger.programWeek.warning("Cannot start a locked ProgramWeek.")
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
