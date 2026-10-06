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
    var workoutExerciseValue: WorkoutExercise?

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
    }
}

//
// Public Accessors
//
extension WorkoutSet {
    // Order
    var order: Int { orderValue}
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
    // Completed At
    var completedAt: Date? { completedAtValue }
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
    func complete(at date: Date = .now) {
        guard
            !lockedValue,
            status == .active
        else {
            Logger.workoutSet.warning("Cannot complete a locked or skipped WorkoutSet")
            return
        }
        statusValue = Status.complete
        completedAtValue = date
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
        completedAtValue = nil
        Logger.workoutSet.debug("Starting WorkoutSet")
    }
}
