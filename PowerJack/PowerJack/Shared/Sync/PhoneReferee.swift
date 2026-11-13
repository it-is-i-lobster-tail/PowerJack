//
//  PhoneReferee.swift
//  PowerJack
//
//  The iPhone's side of the direct link with the watch. It applies what the watch did, refereeing
//  any set both devices logged, and answers with its program, which the watch then follows.
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class PhoneReferee {
    private static let appliedKey = "sync.appliedWatchChanges"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last change applied from each watch install.
    private(set) var applied: [String: Int] {
        get { defaults.dictionary(forKey: Self.appliedKey) as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: Self.appliedKey) }
    }

    /// The program to send the watch.
    func snapshot(in context: ModelContext) throws -> ProgramSnapshot {
        try ProgramSnapshot.make(in: context, applied: applied)
    }

    /// Applies every change not applied yet, in order, tidies up, and answers with the program.
    func receive(_ changes: [WatchChange], in context: ModelContext) throws -> ProgramSnapshot {
        var applied = self.applied
        let programs = try context.fetch(FetchDescriptor<Program>())
        for change in changes.sorted(by: { $0.id < $1.id }) {
            let install = change.install.uuidString
            guard change.id > applied[install, default: 0] else { continue }
            // A program the iPhone doesn't have is never mistaken for the running one.
            let program = change.row.program.map { id in programs.first { $0.syncID == id } } ?? programs.active
            if program.map({ change.apply(to: $0, in: context) }) != true {
                // Counted as applied all the same, so one the iPhone can't place never holds up the rest.
                Logger.sync.warning("Couldn't find the row a watch change names")
            }
            applied[install] = change.id
        }
        try context.save()
        self.applied = applied
        try SyncTidyUp.run(in: context)
        return try snapshot(in: context)
    }
}

extension WatchChange {
    /// Does on the iPhone what the watch did, the same way the watch's screens did it.
    /// - Returns: false when the iPhone has no row where the change names one.
    func apply(to program: Program, in context: ModelContext) -> Bool {
        switch action {
        case .startWorkout:
            guard let workout = program.workout(at: row) else { return false }
            if workout.status == .planned && workout.locked {
                program.prepareToStart(workout, at: date)
                workout.startAndCascade(at: date, on: SyncDevice.watch)
            }
        case .logSet(let log):
            guard let workoutSet = program.workoutSet(at: row), let workoutExercise = workoutSet.workoutExerciseValue else { return false }
            referee(log, on: workoutSet, of: workoutExercise, in: context)
        case .skipWarmups:
            guard let workoutExercise = program.workoutExercise(at: row) else { return false }
            if !workoutExercise.locked { workoutExercise.skipWarmups() }
        case .rateExercise(let feedback, let topSetRepsInReserve):
            guard let workoutExercise = program.workoutExercise(at: row) else { return false }
            // Feedback already answered on the iPhone stands.
            let topSet = topSetRepsInReserve.flatMap(RepsInReserve.init(rawValue:))
            workoutExercise.answerFeedback(ExerciseFeedback(snapshot: feedback), topSet: topSet)
        case .resolveCheckIn(let decisionName):
            guard let workoutExercise = program.workoutExercise(at: row) else { return false }
            if workoutExercise.checkInPending, let decision = ManualCheckInDecision(rawValue: decisionName) {
                workoutExercise.resolveCheckIn(decision)
            }
        case .finishWorkout:
            guard let workout = program.workout(at: row) else { return false }
            if workout.status == .active {
                workout.skipRemainingSets()
                program.finishWorkout(workout)
            }
        }
        return true
    }

    /// A set the iPhone hasn't logged takes the watch's log. One both logged keeps the referee's
    /// winner, stamped after both logs, so the receipts (latest log wins) agree with it later.
    private func referee(_ log: SetLog, on workoutSet: WorkoutSet, of workoutExercise: WorkoutExercise, in context: ModelContext) {
        guard var iPhoneLog = workoutSet.log else {
            guard let reps = log.reps else { return }
            workoutExercise.log(weightTenthsPounds: log.weightTenthsPounds, reps: reps, on: workoutSet, at: log.completedAt, device: SyncDevice.watch)
            return
        }
        iPhoneLog.isCorrection = SetReceipt.wasLogged(workoutSet, before: iPhoneLog.completedAt, in: context)
        guard !iPhoneLog.holdsSameValues(as: log) else { return }

        let winner = SetReferee.winner(iPhone: iPhoneLog, watch: log, together: together)
        let stamp = max(iPhoneLog.completedAt, log.completedAt).addingTimeInterval(0.001)
        workoutSet.restamp(winner == .watch ? log : iPhoneLog, at: stamp)
        context.insert(SetReceipt(for: workoutSet, device: winner == .watch ? SyncDevice.watch : SyncDevice.iPhone))
        Logger.sync.info("Both devices logged a set; the \(winner == .watch ? "watch" : "iPhone", privacy: .public)'s log stands")
    }
}
