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
    @Relationship(deleteRule: .nullify, inverse: \Exercise.workoutExercisesValue)
    private var exerciseValue: Exercise?
    private var orderValue: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workoutExerciseValue)
    private var workoutSetsValue: [WorkoutSet]? = []
    private var statusValue: Status = Status.planned
    private var lockedValue: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \ExerciseFeedback.workoutExerciseValue)
    private var feedbackValue: ExerciseFeedback?
    private var checkInValue: ManualCheckIn = ManualCheckIn.none
    private var checkInSourcePainValue: LevelOfPain?
    var workoutValue: Workout?

    /// Working sets only. Warmups don't count toward this.
    static let maxSets = 5
    static let initialSets = 2
    static let initialWarmupSets = 2

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
    // Exercise. Optional because a synced row can arrive before its exercise.
    var exercise: Exercise? { exerciseValue }
    // Order
    var order: Int {
        get { orderValue }
        set { orderValue = newValue }
    }
    // WorkoutSets
    var workoutSets: [WorkoutSet] { (workoutSetsValue ?? []).sorted(byOrder: \.order) }
    // Warmups always come before working sets.
    var warmupSets: [WorkoutSet] { workoutSets.filter(\.isWarmup) }
    var workingSets: [WorkoutSet] { workoutSets.filter { !$0.isWarmup } }
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
    var totalSets: Int { workoutSetsValue?.count ?? 0 }
    // Completed Sets
    func getCountCompletedSets() -> Int {
        return countSetStatus(status: Status.complete)
    }
    // Completed working sets. The only sets that count toward progression and the summary.
    var completedWorkingSets: Int {
        workingSets.count(where: { $0.status == .complete })
    }
    /// 1-based position within the set's own type, e.g. the first working set is 1 after two warmups.
    func number(of workoutSet: WorkoutSet) -> Int {
        let sameType = workoutSet.isWarmup ? warmupSets : workingSets
        return (sameType.firstIndex { $0 === workoutSet } ?? 0) + 1
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
            completedWorkingSets > 0
    }
    // All Sets Complete
    func allSetsDone() -> Bool {
        let sets = workoutSetsValue ?? []
        return !sets.isEmpty &&
                sets.allSatisfy { workoutSet in
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
        for workoutSet in workoutSets {
            workoutSet.completeAndLock()
        }
    }
    func stopAndCascade() {
        stop()
        for workoutSet in workoutSets {
            workoutSet.stop()
        }
    }
    func skipAndCascade() {
        skip()
        for workoutSet in workoutSets {
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

        for workoutSet in workoutSets {
            workoutSet.start()
        }
    }
    func addSet(
        type: SetType = .working,
        plannedReps: Int? = nil,
        plannedWeightTenthsPounds: Int? = nil
    ) -> WorkoutSet? {
        guard
            !lockedValue,
            canAddSet(type: type)
        else {
            Logger.workoutExercise.warning("Unable to add WorkoutSet to WorkoutExercise. Max sets exceeded or workoutExercise is locked.")
            return nil
        }

        let nextOrder = totalSets
        let lastSetWeight = (type == .warmup ? warmupSets : workingSets).last?.weightTenthsPounds
        let newSet = WorkoutSet(
            order: nextOrder,
            setType: type,
            plannedReps: plannedReps,
            plannedWeightTenthsPounds: plannedWeightTenthsPounds ?? lastSetWeight,
        )
        newSet.start()
        workoutSetsValue = (workoutSetsValue ?? []) + [newSet]
        Logger.workoutExercise.debug("Added new WorkoutSet to WorkoutExercise")
        return newSet
    }
    /// Adds a set that stays planned until the workout starts. Used for generated weeks.
    @discardableResult
    func addPlannedSet(
        type: SetType = .working,
        plannedReps: Int?,
        plannedWeightTenthsPounds: Int?
    ) -> WorkoutSet? {
        guard
            status == .planned,
            canAddSet(type: type)
        else {
            Logger.workoutExercise.warning("Unable to add planned WorkoutSet. Max sets exceeded or WorkoutExercise already started.")
            return nil
        }
        let newSet = WorkoutSet(
            order: totalSets,
            setType: type,
            plannedReps: plannedReps,
            plannedWeightTenthsPounds: plannedWeightTenthsPounds
        )
        workoutSetsValue = (workoutSetsValue ?? []) + [newSet]
        return newSet
    }
    /// Adds the warmup sets every exercise starts with. Call before adding working sets.
    func addWarmupSets() {
        for _ in 0..<Self.initialWarmupSets {
            _ = addSet(type: .warmup)
        }
    }
    /// Warmups are capped and must come before any working set; working sets are capped at `maxSets`.
    private func canAddSet(type: SetType) -> Bool {
        switch type {
        case .warmup: warmupSets.count < Self.initialWarmupSets && workingSets.isEmpty
        case .working: workingSets.count < Self.maxSets
        }
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
            deleteAllSets()
            startAndCascade()
            addInitialSets()
        case .skip:
            skipAndCascade()
        }
        Logger.workoutExercise.info("Resolved manual check-in for \(self.exercise?.exerciseName ?? "an exercise")")
    }
    /// Removes the last working set. Warmups stay.
    func removeLastSet() {
        guard !lockedValue, let lastSet = workingSets.last else {
            Logger.workoutExercise.warning("Cannot remove last working set of locked or empty WorkoutExercise.")
            return
        }
        Logger.workoutExercise.info("Removing set from WorkoutExercise \(self.exercise?.exerciseName ?? "an exercise")")
        workoutSetsValue?.removeAll { $0 === lastSet }
        // Delete the row too, so it doesn't linger (or sync) as an orphan.
        modelContext?.delete(lastSet)
    }
    private func deleteAllSets() {
        let sets = workoutSets
        workoutSetsValue = []
        for workoutSet in sets {
            modelContext?.delete(workoutSet)
        }
    }
    func changeExercise(newExercise: Exercise) {
        guard !lockedValue else {
            Logger.workoutExercise.warning("Cannot change Exercise of locked WorkoutExercise")
            return
        }
        Logger.workoutExercise.info("Changing \(self.exercise?.exerciseName ?? "an exercise") to \(newExercise.exerciseName) and resetting progression.")
        exerciseValue = newExercise
        deleteAllSets()
        addInitialSets()
    }
    private func addInitialSets() {
        addWarmupSets()
        for _ in 0..<Self.initialSets {
            _ = addSet()
        }
    }
    /// Points a row at the surviving copy of a duplicated catalog exercise. Logged sets are kept.
    func replaceDuplicateExercise(with survivor: Exercise) {
        exerciseValue = survivor
    }
    /// Copies a weight entered on `workoutSet` to every later set of the same type still being logged.
    /// Completed and skipped sets keep what was logged, and warmup weights never reach working sets.
    func applyWeight(_ weightTenthsPounds: Int?, after workoutSet: WorkoutSet) {
        guard let weightTenthsPounds else { return }
        for laterSet in workoutSets where laterSet.order > workoutSet.order &&
            laterSet.setType == workoutSet.setType &&
            laterSet.status == .active {
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
