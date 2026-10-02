//
//  WorkoutSet.swift
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
    private var repsPlannedValue: Int?
    private var weightTenthsPoundsValue: Int?
    private var weightTenthsPoundsPlannedValue: Int?
    private var statusValue: Status
    private var lockedValue: Bool

    init(
        order: Int,
        plannedReps: Int?,
        plannedWeightTenthsPounds: Int?,
    ) {
        self.orderValue = order
        self.repsPlannedValue = plannedReps.flatMap { Self.isValidReps($0) ? $0 : nil }
        self.weightTenthsPoundsPlannedValue = plannedWeightTenthsPounds
        self.statusValue = .planned
        self.lockedValue = false
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

            if let newValue, newValue > 0 {
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
}
//
// Derived Values
//
extension WorkoutSet {
    /// Reps above `Exercise.maxRepsAllowed` can never be saved.
    static func isValidReps(_ reps: Int) -> Bool {
        (1...Exercise.maxRepsAllowed).contains(reps)
    }
    // Complete or skipped
    var isDone: Bool { status == .complete || status == .skipped }
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
            guard status == .active else { return }
            if let newValue, newValue > 0 {
                weightTenthsPlannedPounds = Int(newValue * 10)
            }
        }
    }
}

//
// Mutations
//

extension WorkoutSet {
    func completeAndLock() {
        guard
            !lockedValue,
            status == .active || status == .complete
        else {
            Logger.workoutSet.warning("Cannot complete a locked or skipped WorkoutSet")
            return
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.workoutSet.debug("WorkoutSet Completed and locked")
    }
    func complete() {
        guard
            !lockedValue,
            status == .active
        else {
            Logger.workoutSet.warning("Cannot complete a locked or skipped WorkoutSet")
            return
        }
        statusValue = Status.complete
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
    func start() {
        guard
            !lockedValue
        else {
            Logger.workoutSet.warning("Can only start a WorkoutSet that is not locked.")
            return
        }

        statusValue = Status.active
        Logger.workoutSet.debug("Starting WorkoutSet")
    }
}
