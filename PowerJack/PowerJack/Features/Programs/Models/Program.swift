//
//  Program.swift
//  PowerJack
//
//  Created on 6/28/26.
//

import Foundation
import SwiftData
import OSLog

@Model
final class Program {
    // Defaults and optional relationships keep the model CloudKit-ready.
    var programLengthWeeksValue: Int = 1
    var statusValue: Status = Status.planned
    @Relationship(deleteRule: .nullify, inverse: \TemplateProgram.programsValue)
    var templateProgramValue: TemplateProgram?
    @Relationship(deleteRule: .cascade, inverse: \ProgramWeek.programValue)
    var programWeeksValue: [ProgramWeek]? = []
    var lockedValue: Bool = false
    // Copied from the template at creation, so later template edits can't change a running
    // program. Rows saved before these existed read 0 / "" / [] and fall back (see below).
    var workoutsPerWeekValue: Int = 0
    var templateNameValue: String = ""
    var templateMuscleFocusValue: [Muscle] = []
    // Optional only in storage: rows from before template types (1.0.13 and earlier, also when
    // iCloud brings them in later) have no value, and upgrading leaves it empty. Read `templateType`.
    private var templateTypeValue: TemplateType? = TemplateType.hypertrophy
    // The same on the iPhone and the watch (see `SyncState`). Nil on rows saved before it existed.
    var syncIDValue: UUID?
    // True when the watch made this row from the iPhone's snapshot.
    var fromSnapshotValue: Bool = false

    private static var programWeekValueMax = 12
    private static var initialWeekSets = 2

    init(programLengthWeeks: Int, templateProgram: TemplateProgram) {
        self.programLengthWeeksValue = min(
            Self.programWeekValueMax,
            max(1, programLengthWeeks)
        )
        self.statusValue = .planned
        self.templateProgramValue = templateProgram
        self.workoutsPerWeekValue = templateProgram.workoutsPerWeek
        self.templateNameValue = templateProgram.templateName
        self.templateMuscleFocusValue = templateProgram.templateMuscleFocus
        self.templateTypeValue = templateProgram.templateType
        self.programWeeksValue = []
        self.lockedValue = false
        self.syncIDValue = UUID()
        buildInitialProgramWeeks()
        setupInitialProgramWeek()
        if let firstWeek = programWeeks.first {
            templateType.weekPlanner.setUpFirstWeek(firstWeek, in: self)
        }
    }

    /// The watch's copy of a program it got from the iPhone, filled in by `apply(_:)`. It has no
    /// template: a program keeps its own copy of what it needs from one.
    init(snapshot state: ProgramState) {
        self.programWeeksValue = []
        self.fromSnapshotValue = true
        apply(state)
    }

    private func buildInitialProgramWeeks() {
        for _ in 0..<programLengthWeeksValue {
            _ = addProgramWeek()
        }
    }

    private func setupInitialProgramWeek() {
        guard let firstWeek = programWeeks.first else {
            Logger.program.warning("Cannot set up initial ProgramWeek because Program has no weeks.")
            return
        }

        for templateWorkout in templateProgram?.templateWorkouts ?? [] {
            guard let newWorkout = firstWeek.addWorkout() else {
                Logger.program.warning("Unable to add Workout to initial ProgramWeek.")
                continue
            }

            for templateExercise in templateWorkout.templateExercises {
                guard
                    let exercise = templateExercise.exercise,
                    let newWorkoutExercise = newWorkout.addWorkoutExercise(exercise: exercise)
                else {
                    Logger.program.warning("Unable to add WorkoutExercise to an initial ProgramWeek's Workout.")
                    continue
                }

                newWorkoutExercise.setSuperset(templateExercise.supersetID)
                newWorkoutExercise.addWarmupSets()
                for _ in 0..<Self.initialWeekSets {
                    _ = newWorkoutExercise.addSet()
                }
            }
        }
    }
}

//
// Public Accessors
//
extension Program {
    // Status
    var status: Status { statusValue }
    // Program Length
    var programLengthWeeks: Int { programLengthWeeksValue }
    // Program Weeks
    var programWeeks: [ProgramWeek] { (programWeeksValue ?? []).sorted(byOrder: \.order) }
    // Template Program. Optional because a synced Program can arrive before its template.
    var templateProgram: TemplateProgram? { templateProgramValue }
}

extension Program: StatusProviding {}

//
// Derived Values
//
extension Program {
    private var allWorkouts: [Workout] {
        var workouts: [Workout] = []
        for programWeek in self.programWeeks {
            for workout in programWeek.workouts {
                workouts.append(workout)
            }
        }
        return workouts
    }

    var totalWorkouts: Int { programLengthWeeks * workoutsPerWeek }

    // The program's own copy of its template's details. Programs saved before the copy existed
    // fall back to week 1, which was built from the template, and then to the template itself.
    var templateName: String {
        if !templateNameValue.isEmpty { return templateNameValue }
        return templateProgram?.templateName ?? "Program"
    }
    var workoutsPerWeek: Int {
        if workoutsPerWeekValue > 0 { return workoutsPerWeekValue }
        if let weekOne = programWeeks.first, !weekOne.workouts.isEmpty { return weekOne.workouts.count }
        return templateProgram?.workoutsPerWeek ?? 0
    }
    var templateMuscleFocus: [Muscle] {
        if !templateMuscleFocusValue.isEmpty { return templateMuscleFocusValue }
        return templateProgram?.templateMuscleFocus ?? []
    }
    /// Picks the progression rules, so it's copied like the rest and never follows template edits.
    /// Programs from before template types are Hypertrophy, the only kind there was.
    var templateType: TemplateType { templateTypeValue ?? .hypertrophy }

    var nextWorkout: Workout? {
        guard status == .active else { return nil }
        let workouts = programWeeks.flatMap(\.workouts)
        return workouts.first { $0.status == .active }
            ?? workouts.first { $0.status == .planned }
    }

    // NOTE: Finished != Complete. Only count skipped or complete.
    var workoutsFinished: Int {
        var c: Int = 0
        for workout in allWorkouts {
            if workout.status == Status.complete || workout.status == Status.skipped {
                c = c + 1
            }
        }
        return c
    }

    /// 1-based week number of the week holding `workout`.
    func weekNumber(containing workout: Workout) -> Int? {
        programWeek(containing: workout).map { $0.order + 1 }
    }

    func programWeek(containing workout: Workout) -> ProgramWeek? {
        programWeeks.first { week in week.workouts.contains { $0 === workout } }
    }

    var percentFinished: Int {
        guard totalWorkouts > 0 else { return 0 }
        return Int(((Double(workoutsFinished) / Double(totalWorkouts)) * 100).rounded())
    }
}

//
// Mutations
//
extension Program {
    func complete() {
        guard
            !lockedValue,
            status == .active
        else {
            Logger.program.warning("Cannot complete a locked Program.")
            return
        }
        statusValue = Status.complete
        lockedValue = true
        Logger.program.debug("Completed Program")
    }
    func stop() {
        guard
            !lockedValue,
            status == .planned || status == .active
        else {
            Logger.program.warning("Cannot stop a locked Program.")
            return
        }
        // What was trained in the week left partway through still counts toward its planner's records.
        if status == .active,
           let week = nextWorkout.flatMap(programWeek(containing:)),
           week.workouts.contains(where: { $0.workoutExercises.contains { $0.completedWorkingSets > 0 } }) {
            templateType.weekPlanner.close(week, in: self)
        }
        statusValue = Status.stopped
        lockedValue = true
        Logger.program.debug("Stopped Program")
    }
    func start() {
        guard
            !lockedValue,
            status == .planned
        else {
            Logger.program.warning("Cannot start a locked or non-planned Program.")
            return
        }
        statusValue = Status.active
        programWeeks.first?.start()
        Logger.program.debug("Started Program")
    }
    /// Lets the program's planner adjust `workout` right before it starts, such as after a long break.
    func prepareToStart(_ workout: Workout, at date: Date = .now) {
        guard status == .active, workout.status == .planned else { return }
        templateType.weekPlanner.prepareToStart(workout, in: self, at: date)
    }
    /// Completes `workout` and moves the program forward.
    /// - Returns: The next workout, already started, or `nil` when the program is finished.
    @discardableResult
    func finishWorkout(_ workout: Workout) -> Workout? {
        guard status == .active else {
            Logger.program.warning("Cannot finish a Workout of a non-active Program.")
            return nil
        }
        if workout.status == .active {
            // Logged before the cascade, which marks any unfinished sets complete.
            logSets(of: workout)
            workout.completeAndCascade()
        }
        return advance(after: workout)
    }
    /// Records the workout's sets in the training history, which outlives the program.
    private func logSets(of workout: Workout) {
        let setsByMuscle = workout.loggedSetsByMuscle
        guard !setsByMuscle.isEmpty else { return }
        modelContext?.insert(WorkoutLog(date: .now, setsByMuscle: setsByMuscle, sessionID: workout.syncID))
    }
    /// Skips the rest of `workout` and moves the program forward.
    /// Completed sets stay completed and count toward history; only unfinished sets are skipped.
    @discardableResult
    func skipWorkout(_ workout: Workout) -> Workout? {
        guard status == .active else {
            Logger.program.warning("Cannot skip a Workout of a non-active Program.")
            return nil
        }
        if workout.status == .planned {
            // Planned workouts are locked; starting unlocks them so they can be skipped.
            workout.startAndCascade()
        }
        if workout.status == .active {
            logSets(of: workout)
        }
        workout.skipAndCascade()
        return advance(after: workout)
    }
    /// A skipped workout can come back while its week is still underway and no other workout is.
    /// Skipping a week's last workout builds the next week from it, so that skip stays.
    func canRestoreWorkout(_ workout: Workout) -> Bool {
        status == .active
            && workout.status == .skipped
            && programWeek(containing: workout)?.status == .active
            && !programWeeks.contains { $0.workouts.contains { $0.status == .active } }
    }
    /// Undoes Skip Workout, taking back the history the skip wrote for its finished sets.
    func restoreWorkout(_ workout: Workout) {
        guard canRestoreWorkout(workout) else {
            Logger.program.warning("Cannot restore this Workout.")
            return
        }
        if let endedAt = workout.endedAt, !workout.loggedSetsByMuscle.isEmpty,
           let log = WorkoutLog.written(near: endedAt, in: modelContext) {
            modelContext?.delete(log)
        }
        workout.unskipAndCascade()
    }
    private func advance(after workout: Workout) -> Workout? {
        if let week = programWeek(containing: workout),
           week.workouts.allSatisfy(\.isFinished) {
            week.complete()
            if let nextWeek = programWeeks.first(where: { $0.order == week.order + 1 }) {
                if nextWeek.workouts.isEmpty {
                    templateType.weekPlanner.build(nextWeek, in: self)
                    // Days edited after they started take the edit from this new week on.
                    for (workout, editedDay) in zip(nextWeek.workouts, week.workouts) {
                        workout.applyNextWeekLayout(from: editedDay)
                    }
                }
                nextWeek.start()
            } else {
                templateType.weekPlanner.close(week, in: self)
            }
        }

        guard let next = nextWorkout else {
            complete()
            completeAndCascade()
            Logger.program.info("Program finished")
            return nil
        }
        // The next workout waits for the user to tap Start Workout.
        return next
    }
    func completeAndCascade() {
        guard status == .complete else {
            Logger.program.warning("Program status must be 'complete' before running completeAndCascade")
            return
        }
        for programWeek in programWeeks {
            programWeek.completeAndCascade()
        }
    }
    func stopAndCascade() {
        guard status == .stopped else {
            Logger.program.warning("Program status must be 'stopped' before running stopAndCascade")
            return
        }
        for programWeek in programWeeks {
            programWeek.stopAndCascade()
        }
    }
    func addProgramWeek() -> ProgramWeek? {
        guard
            !lockedValue,
            programWeeks.count < Self.programWeekValueMax
        else {
            Logger.program.warning("Unable to add ProgramWeek. Max Weeks exceeded or Program is locked.")
            return nil
        }
        let newProgramWeek = ProgramWeek(order: programWeeks.count)
        programWeeksValue = (programWeeksValue ?? []) + [newProgramWeek]
        Logger.program.info("New ProgramWeek added to Program")
        return newProgramWeek
    }
    func removeLastProgramWeek() {
        guard !lockedValue, let lastWeek = programWeeks.last else {
            Logger.program.warning("Cannot remove last ProgramWeek of locked or empty Program.")
            return
        }
        Logger.program.info("Removing last ProgramWeek from Program")
        programWeeksValue?.removeAll { $0 === lastWeek }
        // Delete the row too, so it doesn't linger (or sync) as an orphan.
        modelContext?.delete(lastWeek)
    }
    /// Deletes the program and its weeks, workouts and sets. The active program can't be deleted.
    func delete() {
        guard status != .active else {
            Logger.program.warning("Cannot delete the active Program.")
            return
        }
        modelContext?.delete(self)
    }
}

//
// Sync
//
extension Program {
    var syncID: UUID? { syncIDValue }
    var isFromSnapshot: Bool { fromSnapshotValue }

    /// Gives this program and everything under it sync IDs, for rows saved before they existed.
    /// Only the iPhone does this, so the watch always takes the iPhone's IDs.
    func assignSyncIDs() {
        if syncIDValue == nil { syncIDValue = UUID() }
        for programWeek in programWeeks {
            programWeek.assignSyncIDs()
        }
    }

    var syncState: ProgramState? {
        guard let syncIDValue else { return nil }
        return ProgramState(
            syncID: syncIDValue,
            programLengthWeeks: programLengthWeeksValue,
            status: statusValue,
            locked: lockedValue,
            workoutsPerWeek: workoutsPerWeekValue,
            templateName: templateNameValue,
            templateMuscleFocus: templateMuscleFocusValue,
            templateType: templateType,
            weeks: programWeeks.compactMap(\.syncState)
        )
    }

    /// Makes this row match the iPhone's copy of it. Weeks are matched by the caller.
    func apply(_ state: ProgramState) {
        syncIDValue = state.syncID
        programLengthWeeksValue = state.programLengthWeeks
        statusValue = state.status
        lockedValue = state.locked
        workoutsPerWeekValue = state.workoutsPerWeek
        templateNameValue = state.templateName
        templateMuscleFocusValue = state.templateMuscleFocus
        templateTypeValue = state.templateType
    }

    func attach(_ programWeek: ProgramWeek) {
        programWeeksValue = (programWeeksValue ?? []) + [programWeek]
    }

    func detach(_ programWeek: ProgramWeek) {
        programWeeksValue?.removeAll { $0 === programWeek }
    }

    /// Folds another copy of this program into it: its weeks merge or move over.
    func merge(_ other: Program) {
        if other.statusValue.progress > statusValue.progress {
            statusValue = other.statusValue
            lockedValue = other.lockedValue
        }
        SyncMerge.fold(
            other.programWeeks,
            into: programWeeks,
            key: { $0.syncID.map(AnyHashable.init) },
            merge: { $0.merge($1) },
            move: { other.detach($0); self.attach($0) }
        )
    }

    /// Stops this program because the iPhone, which referees, says another one is running.
    /// The iPhone already closed its week, so only the status changes here.
    func stopForReferee() {
        guard status == .planned || status == .active else { return }
        statusValue = .stopped
        lockedValue = true
    }

    var hasLoggedSets: Bool { programWeeks.contains { $0.workouts.contains(where: \.hasLoggedSets) } }

    var lastLoggedAt: Date? { programWeeks.flatMap(\.workouts).compactMap(\.lastLoggedAt).max() }

    static func fromSnapshot(in context: ModelContext) throws -> [Program] {
        try context.fetch(FetchDescriptor<Program>(predicate: #Predicate { $0.fromSnapshotValue }))
    }
}
