//
//  Item.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation
import SwiftData
import OSLog

@Model
final class WorkoutSet {
    private var orderValue: Int
    private var repsValue: Int?
    private var weightTenthsPoundsValue: Int?
    private var statusValue: Status
    private var lockedValue: Bool

    init(
        order: Int,
        reps: Int?,
        weightTenthsPounds: Int?,
    ) {
        self.orderValue = order
        self.repsValue = reps
        self.weightTenthsPoundsValue = weightTenthsPounds
        self.statusValue = .planned
        self.lockedValue = true
    }
}

//
// Public Accessors
//
extension WorkoutSet {
    // Order
    var order: Int { orderValue}
    // Reps
    var reps: Int? {
        get { repsValue }
        set {
            guard !lockedValue else { return }
            
            if let newValue, newValue > 0 {
                repsValue = newValue
            } else {
                repsValue = nil
            }
        }
    }
    // Weight
    var weightTenthsPounds: Int? {
        get { self.weightTenthsPoundsValue }
        set {
            guard !lockedValue else { return }
            
            if let newValue, newValue > 0 {
                weightTenthsPoundsValue = newValue
            } else {
                weightTenthsPoundsValue = nil
            }
        }
    }
    // Status
    var status: Status { statusValue }
    // Locked
    var locked: Bool { lockedValue }
}
//
// Derived Values
//
extension WorkoutSet {
    var weightInPounds: Double? {
        get {
            guard let weightTenthsPoundsValue else { return nil }
            return Double(weightTenthsPoundsValue) / 10.0
        }
        set {
            guard !lockedValue else { return }
            if let newValue, newValue > 0 {
                weightTenthsPoundsValue = Int(newValue * 10)
            }
        }
    }
}

//
// Mutations
//

extension WorkoutSet {
    func complete() {
        guard !lockedValue else {
            Logger.workoutSet.warning("Attempted to complete a WorkoutSet that cannot be completed.")
            return
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.workoutSet.debug("WorkoutSet Completed")
    }
    func skip() {
        guard !lockedValue else {
            Logger.workoutSet.warning("Attempted to skip a WorkoutSet that cannot be stopped.")
            return
        }
        statusValue = Status.skipped
        lockedValue = true
        Logger.workoutSet.debug("WorkoutSet Stopped")
    }
    func stop() {
        skip()
    }
    func start() {
        guard
            lockedValue,
            statusValue == Status.planned
        else {
            Logger.workoutSet.warning("Attempted to start a WorkoutSet that cannot be started.")
            return
        }

        statusValue = Status.active
        lockedValue = false
        Logger.workoutSet.debug("Starting WorkoutSet")
    }
}
