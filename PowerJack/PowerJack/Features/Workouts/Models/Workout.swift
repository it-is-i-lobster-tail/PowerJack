//
//  Workout.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation
import SwiftData
import OSLog

// ToDo: Restrict appending to `workoutExercisesValue` to an extention function to ensure order is maintained

@Model
final class Workout {
    private var orderValue: Int
    private var workoutExercisesValue: [WorkoutExercise]
    private var statusValue: Status
    private var lockedValue: Bool

    init(
        order: Int
    ){
        self.orderValue = order
        self.workoutExercisesValue = []
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
    var workoutExercises: [WorkoutExercise] { workoutExercisesValue.sorted {$0.order < $1.order} }
    // Status
    var status: Status { statusValue }
    // Locked
    var locked: Bool { lockedValue }
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

    /// Where the user should be: the first exercise still being logged or waiting on feedback.
    /// Derived from stored state so it survives relaunches.
    var currentExerciseIndex: Int {
        let exercises = workoutExercises
        return exercises.firstIndex { !$0.isFinished || $0.needsFeedback }
            ?? max(0, exercises.count - 1)
    }

    var allExercisesFinished: Bool {
        workoutExercisesValue.allSatisfy { $0.isFinished && !$0.needsFeedback }
    }

    var isFinished: Bool {
        status == .complete || status == .skipped || status == .stopped
    }
}

//
// Mutations
//
extension Workout {
    func complete() {
        guard
            !lockedValue,
            status == .active
        else {
            Logger.workout.warning("Cannot complete a locked Workout.")
            return
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.workout.debug("Completed workout")
    }
    func stop() {
        guard
            !lockedValue,
            status == .planned || status == .active
        else {
            Logger.workout.warning("Cannot stop a locked Workout.")
            return
        }
        statusValue = Status.stopped
        lockedValue = true
        Logger.workout.debug("Stopped workout")
    }
    func skip() {
        guard
            !lockedValue,
            status == .planned || status == .active
        else {
            Logger.workout.warning("Cannot skip a locked Workout.")
            return
        }
        statusValue = Status.skipped
        lockedValue = true
        Logger.workout.debug("Skipped workout")
    }
    func start() {
        guard
            lockedValue,
            status == .planned
        else {
            Logger.workout.warning("Cannot start a locked, skipped, stopped, or completed Workout.")
            return
        }
        statusValue = Status.active
        lockedValue = false
        Logger.workout.debug("Started workout")
    }
    func completeAndCascade() {
        complete()
        for workoutExercise in workoutExercisesValue {
            workoutExercise.completeAndCascade()
        }
    }
    func stopAndCascade() {
        stop()
        for workoutExercise in workoutExercisesValue {
            workoutExercise.stopAndCascade()
        }
    }
    func skipAndCascade() {
        skip()
        for workoutExercise in workoutExercisesValue {
            workoutExercise.skipAndCascade()
        }
    }
    func startAndCascade() {
        start()

        for workoutExercise in workoutExercises {
            workoutExercise.startAndCascade()
        }

    }
    func addWorkoutExercise(exercise: Exercise) -> WorkoutExercise? {
        guard locked else {
            Logger.workout.warning("Cannot add WorkoutExercise to locked Workout")
            return nil
        }
        let newWorkoutExercise = WorkoutExercise(
            exercise: exercise,
            order: workoutExercises.count
        )
        workoutExercisesValue.append(newWorkoutExercise)
        Logger.workout.debug("Added new WorkoutExercise to Workout")
        return newWorkoutExercise
    }
    func removeWorkoutExercise(index: Int) -> WorkoutExercise? {
        guard workoutExercisesValue.indices.contains(index) else { return nil }
        return workoutExercisesValue.remove(at: index)
    }
    // Move WorkoutExercises
    func moveWorkoutExercises(from source: IndexSet, to destination: Int) {
        var ordered = workoutExercises
        ordered.moveAndReorder(from: source, to: destination)
        workoutExercisesValue = ordered
    }

}
