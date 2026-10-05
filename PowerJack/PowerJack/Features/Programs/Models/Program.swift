//
//  Program.swift
//  PowerJack
//
//  Created by Brendon on 6/28/26.
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

    private static var programWeekValueMax = 12
    private static var initialWeekSets = 2

    init(programLengthWeeks: Int, templateProgram: TemplateProgram) {
        self.programLengthWeeksValue = min(
            Self.programWeekValueMax,
            max(1, programLengthWeeks)
        )
        self.statusValue = .planned
        self.templateProgramValue = templateProgram
        self.programWeeksValue = []
        self.lockedValue = false
        buildInitialProgramWeeks()
        setupInitialProgramWeek()
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

    // Template details, with safe fallbacks while a synced template is still arriving.
    var templateName: String { templateProgram?.templateName ?? "Program" }
    var workoutsPerWeek: Int { templateProgram?.workoutsPerWeek ?? 0 }
    var templateMuscleFocus: [Muscle] { templateProgram?.templateMuscleFocus ?? [] }

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
    /// Completes `workout` and moves the program forward.
    /// - Returns: The next workout, already started, or `nil` when the program is finished.
    @discardableResult
    func finishWorkout(_ workout: Workout) -> Workout? {
        guard status == .active else {
            Logger.program.warning("Cannot finish a Workout of a non-active Program.")
            return nil
        }
        if workout.status == .active {
            workout.completeAndCascade()
        }
        return advance(after: workout)
    }
    /// Skips `workout` and moves the program forward.
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
        workout.skipAndCascade()
        return advance(after: workout)
    }
    private func advance(after workout: Workout) -> Workout? {
        if let week = programWeek(containing: workout),
           week.workouts.allSatisfy(\.isFinished) {
            week.complete()
            if let nextWeek = programWeeks.first(where: { $0.order == week.order + 1 }) {
                if nextWeek.workouts.isEmpty {
                    ProgressionPlanner.build(nextWeek, in: self)
                }
                nextWeek.start()
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
