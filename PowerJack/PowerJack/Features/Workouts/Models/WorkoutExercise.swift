//
//  WorkoutExercise.swift
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
    private var feedbackValue: ExerciseFeedback?

    static var maxSets = 4

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
    // Feedback
    var feedback: ExerciseFeedback? { feedbackValue }
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
    // All Sets Complete
    func allSetsDone() -> Bool {
        return !workoutSetsValue.isEmpty &&
                workoutSetsValue.allSatisfy { workoutSet in
                    workoutSet.status == .complete ||
                    workoutSet.status == .skipped
                }
    }
}

//
// Mutations
//
extension WorkoutExercise {
    func complete() {
        guard
            !lockedValue,
            status == .active
        else {
            Logger.workoutExercise.warning("Cannot complete a locked WorkoutExercise.")
            return
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.workoutExercise.debug("WorkoutExercise completed")
    }
    func stop() {
        guard
            !lockedValue,
            status == .planned || status == .active
        else {
            Logger.workoutExercise.warning("Cannot stop a locked WorkoutExercise.")
            return
        }
        statusValue = Status.stopped
        lockedValue = true
        Logger.workoutExercise.debug("WorkoutExercise stopped")
    }
    func skip() {
        guard
            !lockedValue,
            status == .planned || status == .active
        else {
            Logger.workoutExercise.warning("Cannot skip a locked WorkoutExercise.")
            return
        }
        statusValue = Status.skipped
        lockedValue = true
        Logger.workoutExercise.debug("WorkoutExercise skipped")
    }
    func start() {
        guard
            statusValue == .planned
        else {
            Logger.workoutExercise.warning("Can only start a WorkoutExercise that is in the planned state.")
            return
        }
        statusValue = Status.active
        Logger.workoutExercise.debug("WorkoutExercise started")
    }
    func completeAndCascade() {
        complete()
        for workoutSet in self.workoutSetsValue {
            workoutSet.completeAndLock()
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
    func startAndCascade() {
        start()

        for workoutSet in self.workoutSetsValue {
            workoutSet.start()
        }
    }
    func addSet(
        plannedReps: Int? = nil,
        plannedWeightTenthsPounds: Int? = nil
    ) -> WorkoutSet? {
        guard
            !lockedValue,
            workoutSetsValue.count < Self.maxSets
        else {
            Logger.workoutExercise.warning("Unable to add WorkoutSet to WorkoutExercise. Max sets exceeded or workoutExercise is locked.")
            return nil
        }

        let nextOrder = workoutSetsValue.count
        let lastSetWeight = (nextOrder == 0 ? nil : workoutSetsValue[nextOrder - 1].weightTenthsPounds)
        let newSet = WorkoutSet(
            order: nextOrder,
            plannedReps: plannedReps,
            plannedWeightTenthsPounds: plannedWeightTenthsPounds ?? lastSetWeight,
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
            Logger.workoutExercise.warning("Cannot change Exercise of locked WorkoutExercise")
            return
        }
        Logger.workoutExercise.info("Changing \(self.exercise.exerciseName) to \(newExercise.exerciseName) and resetting progression.")
        exerciseValue = newExercise
        workoutSetsValue.removeAll()
        _ = addSet()
        _ = addSet()
    }
    func addFeedback(feedback: ExerciseFeedback) {
        guard !lockedValue else {
            Logger.workoutExercise.debug("Cannot add feedback to locked WorkoutExercise")
            return
        }
        feedbackValue = feedback
    }
}
