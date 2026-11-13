//
//  WatchActions.swift
//  PowerJack
//
//  What the watch's screens do to a workout. Each one changes the watch's copy right away and is
//  kept as a `WatchChange` for the iPhone, which referees it once they're together.
//

import Foundation
import SwiftData

@MainActor
struct WatchActions {
    let replica: WatchReplica
    /// Whether the watch can reach the iPhone right now.
    let together: Bool

    func start(_ workout: Workout, in program: Program, at date: Date = .now) {
        guard workout.status == .planned && workout.locked else { return }
        program.prepareToStart(workout, at: date)
        workout.startAndCascade(at: date)
        replica.record(.startWorkout, at: RowPath(workout), together: together, date: date)
    }

    func log(_ entry: SetEntry, on workoutSet: WorkoutSet, of workoutExercise: WorkoutExercise, at date: Date = .now) {
        workoutExercise.log(entry, on: workoutSet, at: date)
        guard var log = workoutSet.log else { return }
        log.isCorrection = SetReceipt.wasLogged(workoutSet, before: date, in: workoutSet.modelContext)
        replica.record(.logSet(log), at: RowPath(workoutSet), together: together, date: date)
    }

    func skipWarmups(of workoutExercise: WorkoutExercise) {
        workoutExercise.skipWarmups()
        replica.record(.skipWarmups, at: RowPath(workoutExercise), together: together)
    }

    func rate(_ workoutExercise: WorkoutExercise, feedback: ExerciseFeedback, topSet: RepsInReserve?) {
        // Already answered on the iPhone: its answer stands, so there's nothing to send.
        guard workoutExercise.answerFeedback(feedback, topSet: topSet) else { return }
        replica.record(.rateExercise(feedback.syncState, topSetRepsInReserve: topSet?.rawValue), at: RowPath(workoutExercise), together: together)
    }

    func resolveCheckIn(of workoutExercise: WorkoutExercise, with decision: ManualCheckInDecision) {
        guard workoutExercise.checkInPending else { return }
        workoutExercise.resolveCheckIn(decision)
        replica.record(.resolveCheckIn(decision.rawValue), at: RowPath(workoutExercise), together: together)
    }

    /// Skips anything still unlogged, then moves the program on. Finishing a week plans the next one.
    func finish(_ workout: Workout, in program: Program) {
        let row = RowPath(workout)
        workout.skipRemainingSets()
        program.finishWorkout(workout)
        replica.record(.finishWorkout, at: row, together: together)
    }
}
