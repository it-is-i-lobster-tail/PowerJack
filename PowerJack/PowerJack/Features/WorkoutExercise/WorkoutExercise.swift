//
//  Lift.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation
import SwiftData
import OSLog

@Model
final class WorkoutExercise {
    private var exerciseValue: Exercise
    private var orderValue: Int
    private var workoutSetsValue: [WorkoutSet]
    private var statusValue: Status
    private var lockedValue: Bool
    
    private static var maxSets = 7

    init(
        exercise: Exercise,
        order: Int,
        workoutSets: [WorkoutSet],
    ){
        self.exerciseValue = exercise
        self.orderValue = order
        self.workoutSetsValue = workoutSets
        self.statusValue = .planned
        self.lockedValue = true
    }
}

//
// Public Accessors
//
extension WorkoutExercise {
    // Exercise
    var exercise: Exercise {
        get { exerciseValue }
        set {
            guard !lockedValue else { return }
            exerciseValue = newValue
        }
    }
    // Order
    var order: Int { orderValue }
    // WorkoutSets
    var workoutSets: [WorkoutSet] { workoutSetsValue }
    // Status
    var status: Status { statusValue }
    // Locked
    var locked: Bool { lockedValue }
}
//
// Derived Values
//
extension WorkoutExercise {
    
    func countSetStatus(status: Status) -> Int {
        var c: Int = 0
        for workoutSet in self.workoutSets {
            if workoutSet.status == status {
                c = c + 1
            }
        }
        return c
    }

    // Total Sets
    var totalSets: Int { workoutSetsValue.count }
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
extension WorkoutExercise {
    func complete() {
        guard !lockedValue else {
            Logger.workoutExercise.warning("Attempted to complete a WorkouExercise that cannot be completed.")
            return
        }
        statusValue = Status.complete
        lockedValue = true
    }
    func stop() {
        guard !lockedValue else {
            Logger.workoutExercise.warning("Attempted to stop a WorkouExercise that cannot be stopped.")
            return
        }
        statusValue = Status.stopped
        lockedValue = true
    }
    func start() {
        guard
            lockedValue,
            statusValue == Status.planned
        else {
            Logger.workoutExercise.warning("Attempted to start a WorkouExercise that cannot be started.")
            return
        }
        statusValue = Status.active
        lockedValue = false
    }
    func completeAndCascade() {
        complete()
        for workoutSet in self.workoutSetsValue {
            workoutSet.complete()
        }
    }
    func stopAndCascade() {
        stop()
        for workoutSet in self.workoutSetsValue {
            workoutSet.stop()
        }
    }
    func startandCascade() {
        start()

        for workoutSet in self.workoutSetsValue {
            workoutSet.start()
        }
    }
    func addSet() {
        guard
            !lockedValue,
            workoutSetsValue.count <= 7
        else {
            Logger.workoutExercise.warning("Unable to addSet to WorkoutExercise. Max sets exceeded or workoutExercise is locked.")
            return
        }

        Logger.workoutExercise.info("Adding a new set to WorkoutExercise \(self.exercise.exerciseName)")
        let nextOrder = workoutSetsValue.count
        let lastSetWeight = (nextOrder == 0 ? 0 : workoutSetsValue[nextOrder - 1].weightTenthsPounds)
        let newSet = WorkoutSet(
            order: nextOrder,
            reps: nil,
            weightTenthsPounds: lastSetWeight,
        )
        newSet.start()
        workoutSetsValue.append(newSet)
    }
    func removeLastSet() -> WorkoutSet? {
        guard !lockedValue else {
            Logger.workoutExercise.warning("Unable to remove a set from WorkoutExercise. WorkoutExercise is locked.")
            return nil
        }
        Logger.workoutExercise.info("Removing set from WorkoutExercise \(self.exercise.exerciseName)")
        return workoutSetsValue.popLast()
    }
    func changeExercise(newExercise: Exercise) {
        guard !lockedValue else {
            Logger.workoutExercise.warning("Unable to change Exercise of WorkoutExercise. WorkoutExercise is locked.")
            return
        }
        Logger.workoutExercise.info("Changing \(self.exercise.exerciseName) to \(newExercise.exerciseName) and resetting progression.")
        exerciseValue = newExercise
        workoutSetsValue.removeAll()
        addSet()
        addSet()
    }
}
