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
    private var orderValue: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workoutValue)
    private var workoutExercisesValue: [WorkoutExercise]? = []
    private var statusValue: Status = Status.planned
    private var lockedValue: Bool = true
    // When Start Workout was tapped, and when the workout was finished, stopped, or skipped.
    private var startedAtValue: Date? = nil
    private var endedAtValue: Date? = nil
    var programWeekValue: ProgramWeek?
    // The day's exercises from next week on, saved when it's edited after it started this week.
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.nextWeekWorkoutValue)
    private var nextWeekExercisesValue: [TemplateExercise]? = []
    // Whether `nextWeekExercisesValue` holds an edit, so an edit that removes every exercise still counts.
    private var hasNextWeekLayoutValue: Bool = false

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
    var workoutExercises: [WorkoutExercise] { (workoutExercisesValue ?? []).sorted(byOrder: \.order) }
    // Status
    var status: Status { statusValue }
    // Locked
    var locked: Bool { lockedValue }
    // Started At
    var startedAt: Date? { startedAtValue }
    // Ended At
    var endedAt: Date? { endedAtValue }
}

//
// Derived Values
//
extension Workout {
    func countSetStatus(status: Status) -> Int {
        var c: Int = 0
        for workout in workoutExercises {
            c = c + workout.countSetStatus(status: status)
        }
        return c
    }

    // Total Sets
    var totalSets: Int {
        var c: Int = 0
        for workout in workoutExercises {
            c = c + workout.totalSets
        }
        return c
    }
    // Completed Sets
    func getCountCompletedSets() -> Int {
        return countSetStatus(status: Status.complete)
    }
    // Working sets only, for progress. Warmups are optional.
    var workingSetCount: Int {
        workoutExercises.reduce(0) { $0 + $1.workingSets.count }
    }
    var completedWorkingSets: Int {
        workoutExercises.reduce(0) { $0 + $1.completedWorkingSets }
    }
    var skippedWorkingSets: Int {
        // A skipped workout counts every set it never finished.
        if status == .skipped { return workingSetCount - completedWorkingSets }
        return workoutExercises.reduce(0) { $0 + $1.workingSets.count(where: { $0.status == .skipped }) }
    }
    /// Completed working sets out of all working sets, 0-100. Warmups and skipped sets don't count.
    var percentComplete: Int {
        let total = workingSetCount
        guard total > 0 else { return 0 }
        return Int((Double(completedWorkingSets) / Double(total) * 100).rounded())
    }
    /// Share of working sets completed and skipped. Both count as resolved.
    var setProgress: (completed: Double, skipped: Double) {
        let total = workingSetCount
        guard total > 0 else { return (0, status == .skipped ? 1 : 0) }
        return (Double(completedWorkingSets) / Double(total), Double(skippedWorkingSets) / Double(total))
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
    /// In a superset, that's the exercise whose turn it is. Derived from stored state so it survives relaunches.
    var currentExerciseIndex: Int {
        let exercises = workoutExercises
        guard let index = exercises.firstIndex(where: { !$0.isDone }) else {
            return max(0, exercises.count - 1)
        }
        guard
            !exercises[index].allSetsDone(),
            let next = currentSet?.workoutExercise,
            exercises[index].supersetPartners.contains(where: { $0 === next }),
            let nextIndex = exercises.firstIndex(where: { $0 === next })
        else {
            return index
        }
        return nextIndex
    }

    var allExercisesFinished: Bool {
        workoutExercises.allSatisfy(\.isDone)
    }

    /// Working sets not yet logged or skipped, shown before the workout is finished.
    var remainingWorkingSets: Int {
        workoutExercises.reduce(0) { count, workoutExercise in
            count + workoutExercise.workingSets.count { !$0.isDone }
        }
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
        endedAtValue = .now
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
        endedAtValue = .now
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
        endedAtValue = .now
        Logger.workout.debug("Skipped workout")
    }
    func start(at date: Date = .now) {
        guard
            lockedValue,
            status == .planned
        else {
            Logger.workout.warning("Cannot start a locked, skipped, stopped, or completed Workout.")
            return
        }
        statusValue = Status.active
        lockedValue = false
        startedAtValue = date
        Logger.workout.debug("Started workout")
    }
    func completeAndCascade() {
        complete()
        for workoutExercise in workoutExercises {
            workoutExercise.completeAndCascade()
        }
    }
    func stopAndCascade() {
        stop()
        for workoutExercise in workoutExercises {
            workoutExercise.stopAndCascade()
        }
    }
    func skipAndCascade() {
        skip()
        for workoutExercise in workoutExercises {
            workoutExercise.skipAndCascade()
        }
    }
    /// Undoes Skip Workout. With a set logged it's in progress again, right where it was left.
    /// With nothing logged it's planned again, so Start Workout runs as it would have.
    func unskipAndCascade() {
        guard status == .skipped else {
            Logger.workout.warning("Can only unskip a skipped Workout.")
            return
        }
        let wasLogged = workoutExercises.contains { $0.workoutSets.contains { $0.status == .complete } }
        endedAtValue = nil
        if wasLogged {
            statusValue = Status.active
            lockedValue = false
            for workoutExercise in workoutExercises {
                workoutExercise.unskipWorkout()
            }
        } else {
            statusValue = Status.planned
            lockedValue = true
            startedAtValue = nil
            for workoutExercise in workoutExercises {
                workoutExercise.resetToPlanned()
            }
        }
        Logger.workout.debug("Unskipped workout")
    }
    func startAndCascade(at date: Date = .now) {
        start(at: date)

        for workoutExercise in workoutExercises {
            workoutExercise.startAndCascade()
        }

    }
    /// Skips every set still to do, so finishing never marks an unlogged set complete.
    func skipRemainingSets() {
        for workoutExercise in workoutExercises where !workoutExercise.allSetsDone() {
            workoutExercise.skipRemainingSets()
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
        workoutExercisesValue = (workoutExercisesValue ?? []) + [newWorkoutExercise]
        Logger.workout.debug("Added new WorkoutExercise to Workout")
        return newWorkoutExercise
    }
    func removeWorkoutExercise(index: Int) {
        let exercises = workoutExercises
        guard exercises.indices.contains(index) else { return }
        let removed = exercises[index]
        workoutExercisesValue?.removeAll { $0 === removed }
        // Delete the row too, so it doesn't linger (or sync) as an orphan.
        modelContext?.delete(removed)
    }
    /// Rebuilds a planned workout's exercises from `layout`, in order. Exercises it keeps keep their planned sets;
    /// new ones start like a swapped-in exercise, with warmups and two sets. Returns the exercises in order.
    @discardableResult
    func applyLayout(_ layout: [(workoutExercise: WorkoutExercise?, exercise: Exercise, supersetID: UUID?)]) -> [WorkoutExercise] {
        guard status == .planned else {
            Logger.workout.warning("Can only change the exercises of a planned Workout.")
            return workoutExercises
        }
        let kept = Set(layout.compactMap { $0.workoutExercise.map(ObjectIdentifier.init) })
        for removed in workoutExercises where !kept.contains(ObjectIdentifier(removed)) {
            workoutExercisesValue?.removeAll { $0 === removed }
            // Delete the row too, so it doesn't linger (or sync) as an orphan.
            modelContext?.delete(removed)
        }

        let ordered = layout.compactMap { entry -> WorkoutExercise? in
            if let workoutExercise = entry.workoutExercise { return workoutExercise }
            guard let added = addWorkoutExercise(exercise: entry.exercise) else { return nil }
            added.addWarmupSets()
            for _ in 0..<WorkoutExercise.initialSets {
                _ = added.addSet()
            }
            return added
        }
        for (order, (workoutExercise, entry)) in zip(ordered, layout).enumerated() {
            workoutExercise.order = order
            workoutExercise.setSuperset(entry.supersetID)
        }
        Logger.workout.debug("Changed the exercises of a planned Workout")
        return ordered
    }
    /// The day's exercises from next week on, when it was edited after it started. Nil when no edit is waiting.
    var nextWeekLayout: [TemplateExercise]? {
        hasNextWeekLayoutValue ? (nextWeekExercisesValue ?? []).sorted(byOrder: \.order) : nil
    }
    /// Saves the exercises this day has from next week on. This week's stay as they were.
    func setNextWeekLayout(_ layout: [(exercise: Exercise, supersetID: UUID?)]) {
        clearNextWeekLayout()
        nextWeekExercisesValue = layout.enumerated().map { order, entry in
            TemplateExercise(exercise: entry.exercise, order: order, supersetID: entry.supersetID)
        }
        hasNextWeekLayoutValue = true
    }
    func clearNextWeekLayout() {
        for row in nextWeekExercisesValue ?? [] {
            modelContext?.delete(row)
        }
        nextWeekExercisesValue = []
        hasNextWeekLayoutValue = false
    }
    /// Gives this newly built workout the exercises its day was edited to last week, then clears that edit.
    /// Exercises it already has keep the sets the planner gave them.
    func applyNextWeekLayout(from source: Workout) {
        guard let layout = source.nextWeekLayout else { return }
        var unclaimed = workoutExercises
        applyLayout(layout.compactMap { row in
            guard let exercise = row.exercise else { return nil }
            let match = unclaimed.firstIndex { $0.exercise === exercise }.map { unclaimed.remove(at: $0) }
            return (workoutExercise: match, exercise: exercise, supersetID: row.supersetID)
        })
        source.clearNextWeekLayout()
    }
    // Move WorkoutExercises
    func moveWorkoutExercises(from source: IndexSet, to destination: Int) {
        var ordered = workoutExercises
        ordered.moveAndReorder(from: source, to: destination)
        workoutExercisesValue = ordered
    }

}
