//
//  WorkoutExercise.swift
//  PowerJack
//
//  Created by Brendon on 6/24/26.
//

import Foundation
import SwiftData
import OSLog

/// Severe pain holds an exercise until the user decides how to continue.
enum ManualCheckIn: String, Codable {
    case none
    case pending
    case resolved
}

enum ManualCheckInDecision: CaseIterable, Identifiable {
    /// Keep the held prescription and log it.
    case `continue`
    /// Replace the held prescription with two fresh sets.
    case reset
    /// Skip this exercise for this workout.
    case skip

    var id: Self { self }
}

@Model
final class WorkoutExercise {
    private var exerciseValue: Exercise
    private var orderValue: Int
    private var workoutSetsValue: [WorkoutSet]
    private var statusValue: Status
    private var lockedValue: Bool
    @Relationship(deleteRule: .cascade)
    private var feedbackValue: ExerciseFeedback?
    private var checkInValue: ManualCheckIn = ManualCheckIn.none
    private var checkInSourcePainValue: LevelOfPain?

    static let maxSets = 5
    static let initialSets = 2

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
    // Manual Check-In
    var checkIn: ManualCheckIn { checkInValue }
    var checkInSourcePain: LevelOfPain? { checkInSourcePainValue }
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
    var checkInPending: Bool { checkInValue == .pending }
    // Complete, skipped, or stopped.
    var isFinished: Bool {
        status == .complete || status == .skipped || status == .stopped
    }
    // Every set is logged but the user has not rated the exercise yet.
    var needsFeedback: Bool {
        feedbackValue == nil &&
            (status == .active || status == .skipped) &&
            allSetsDone() &&
            getCountCompletedSets() > 0
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
        guard checkInValue != .pending else {
            // Stays planned and locked until `resolveCheckIn` runs.
            lockedValue = true
            Logger.workoutExercise.debug("WorkoutExercise waiting on manual check-in")
            return
        }
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
    /// Adds a set that stays planned until the workout starts. Used for generated weeks.
    @discardableResult
    func addPlannedSet(
        plannedReps: Int?,
        plannedWeightTenthsPounds: Int?
    ) -> WorkoutSet? {
        guard
            status == .planned,
            workoutSetsValue.count < Self.maxSets
        else {
            Logger.workoutExercise.warning("Unable to add planned WorkoutSet. Max sets exceeded or WorkoutExercise already started.")
            return nil
        }
        let newSet = WorkoutSet(
            order: workoutSetsValue.count,
            plannedReps: plannedReps,
            plannedWeightTenthsPounds: plannedWeightTenthsPounds
        )
        workoutSetsValue.append(newSet)
        return newSet
    }
    /// Holds this planned exercise behind a manual check-in (pain was severe last time).
    func requireCheckIn(sourcePain: LevelOfPain) {
        guard status == .planned else {
            Logger.workoutExercise.warning("Can only require a check-in on a planned WorkoutExercise.")
            return
        }
        checkInValue = .pending
        checkInSourcePainValue = sourcePain
        lockedValue = true
    }
    func resolveCheckIn(_ decision: ManualCheckInDecision) {
        guard checkInValue == .pending else {
            Logger.workoutExercise.warning("WorkoutExercise does not need a manual check-in.")
            return
        }
        checkInValue = .resolved
        lockedValue = false

        switch decision {
        case .continue:
            startAndCascade()
        case .reset:
            workoutSetsValue.removeAll()
            startAndCascade()
            for _ in 0..<Self.initialSets {
                _ = addSet()
            }
        case .skip:
            skipAndCascade()
        }
        Logger.workoutExercise.info("Resolved manual check-in for \(self.exercise.exerciseName)")
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
        for _ in 0..<Self.initialSets {
            _ = addSet()
        }
    }
    /// Copies a weight entered on `workoutSet` to every later set still being logged.
    /// Completed and skipped sets keep what was logged.
    func applyWeight(_ weightTenthsPounds: Int?, after workoutSet: WorkoutSet) {
        guard let weightTenthsPounds else { return }
        for laterSet in workoutSets where laterSet.order > workoutSet.order && laterSet.status == .active {
            laterSet.weightTenthsPounds = weightTenthsPounds
        }
    }
    /// Feedback is recorded once every set is done, even after "Skip Remaining Sets" locked the exercise.
    func addFeedback(feedback: ExerciseFeedback) {
        guard allSetsDone(), status == .active || status == .skipped else {
            Logger.workoutExercise.debug("Cannot add feedback before every set is done")
            return
        }
        feedbackValue = feedback
    }
}
