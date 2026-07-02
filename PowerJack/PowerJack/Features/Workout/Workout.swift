//
//  Workout.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation
import SwiftData
import OSLog

@Model
final class Workout {
    private var orderValue: Int
    private var workoutExercisesValue: [WorkoutExercise]
    private var statusValue: Status
    private var lockedValue: Bool
    
    init(
        order: Int,
        workoutExercises: [WorkoutExercise],
    ){
        self.orderValue = order
        self.workoutExercisesValue = workoutExercises
        self.statusValue = .planned
        self.lockedValue = true
    }
}

//
// Public Accessors
//
extension Workout {
    // Order
    var order: Int { orderValue}
    // Workout Exercises
    var workoutExercises: [WorkoutExercise] { workoutExercisesValue }
    // Status
    var status: Status { statusValue }
}

//
// Derived Values
//
extension Workout {
    func countSetStatus(status: Status) -> Int {
        var c: Int = 0
        for workout in self.workoutExercisesValue {
            c = c + workout.countSetStatus(status: status)
        }
        return c
    }
    
    // Total Sets
    var totalSets: Int {
        var c: Int = 0
        for workout in self.workoutExercisesValue {
            c = c + workout.totalSets
        }
        return c
    }
    // Completed Sets
    func getCountCompletedSets() -> Int {
        return countSetStatus(status: Status.complete)
    }
    // Planned Sets
    func getCountPlannedSets() -> Int {
        return countSetStatus(status: Status.planned)
    }
    // Skipped Sets
    func getCountSkippedSets() -> Int {
        return countSetStatus(status: Status.skipped)
    }
    // Active Sets
    func getCountActiveSets() -> Int {
        return countSetStatus(status: Status.active)
    }
}

//
// Mutations
//
extension Workout {
    func complete() {
        guard !lockedValue else {
            Logger.workout.warning("Attempted to complete a WorkouExercise that cannot be completed.")
            return
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.workout.debug("Completed workout")
    }
    func stop() {
        guard !lockedValue else {
            Logger.workout.warning("Attempted to stop a WorkouExercise that cannot be stopped.")
            return
        }
        statusValue = Status.stopped
        lockedValue = true
        Logger.workout.debug("Stopped workout")
    }
    func start() {
        guard
            lockedValue,
            statusValue == Status.planned
        else {
            Logger.workout.warning("Attempted to start a WorkouExercise that cannot be started.")
            return
        }
        statusValue = Status.active
        lockedValue = false
        Logger.workout.debug("Started workout")
    }
    func completeAndCascade() {
        complete()
        for workoutExercise in self.workoutExercisesValue {
            workoutExercise.completeAndCascade()
        }
    }
    func stopAndCascade() {
        stop()
        for workoutExercise in self.workoutExercisesValue {
            workoutExercise.stopAndCascade()
        }
    }
    func startAndCascade() {
        start()

        for workoutExercise in self.workoutExercises {
            workoutExercise.startandCascade()
        }
        
    }
}
