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
    ){
        self.exerciseValue = exercise
        self.orderValue = order
        self.workoutSetsValue = []
        self.statusValue = .planned
        self.lockedValue = false
    }
}

//
// Public Accessors
//
extension WorkoutExercise {
    // Exercise
    var exercise: Exercise {
        get { exerciseValue }
    }
    // Order
    var order: Int {
        get { orderValue }
        set { orderValue = newValue }
    }
    // WorkoutSets
    var workoutSets: [WorkoutSet] { workoutSetsValue.sorted { $0.order < $1.order} }
    // Status
    var status: Status { statusValue }
    // Locked
    var locked: Bool { lockedValue }
}

extension WorkoutExercise: OrderedModel {}
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
            Logger.workoutExercise.warning("Cannot complete a locked WorkoutExercise.")
            return
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.workoutSet.debug("WorkouExercise completed")
    }
    func stop() {
        guard !lockedValue else {
            Logger.workoutExercise.warning("Cannot stop a locked WorkoutExercise.")
            return
        }
        statusValue = Status.stopped
        lockedValue = true
        Logger.workoutSet.debug("WorkouExercise stopped")
    }
    func skip() {
        guard !lockedValue else {
            Logger.workoutExercise.warning("Cannot skip a locked WorkoutExercise.")
            return
        }
        statusValue = Status.skipped
        lockedValue = true
        Logger.workoutSet.debug("WorkouExercise skipped")
    }
    func start() {
        guard
            statusValue == Status.planned
        else {
            Logger.workoutExercise.warning("Can only stat a WorkoutExercise that is in the planned state.")
            return
        }
        statusValue = Status.active
        Logger.workoutSet.debug("WorkouExercise started")
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
    func skipAndCascade() {
        skip()
        for workoutSet in self.workoutSetsValue {
            workoutSet.skip()
        }
    }
    func startandCascade() {
        start()

        for workoutSet in self.workoutSetsValue {
            workoutSet.start()
        }
    }
    func addSet() -> WorkoutSet? {
        guard
            !lockedValue,
            workoutSetsValue.count <= 7
        else {
            Logger.workoutExercise.warning("Unable to add WorkoutSet to WorkoutExercise. Max sets exceeded or workoutExercise is locked.")
            return nil
        }

        let nextOrder = workoutSetsValue.count
        let lastSetWeight = (nextOrder == 0 ? nil : workoutSetsValue[nextOrder - 1].weightTenthsPounds)
        let newSet = WorkoutSet(
            order: nextOrder,
            reps: nil,
            weightTenthsPounds: lastSetWeight,
        )
        newSet.start()
        workoutSetsValue.append(newSet)
        Logger.workoutExercise.debug("Added new WorkoutSet to WorkoutExercise")
        return newSet
    }
    func removeLastSet() -> WorkoutSet? {
        guard !lockedValue else {
            Logger.workoutExercise.warning("Cannot remove last WorkoutSet of locked WorkoutExercise.")
            return nil
        }
        Logger.workoutExercise.info("Removing set from WorkoutExercise \(self.exercise.exerciseName)")
        return workoutSetsValue.popLast()
    }
    func changeExercise(newExercise: Exercise) {
        guard !lockedValue else {
            Logger.workoutExercise.warning("Cannot change Exercise of locked WorkoutExercisez")
            return
        }
        Logger.workoutExercise.info("Changing \(self.exercise.exerciseName) to \(newExercise.exerciseName) and resetting progression.")
        exerciseValue = newExercise
        workoutSetsValue.removeAll()
        _ = addSet()
        _ = addSet()
    }
}
