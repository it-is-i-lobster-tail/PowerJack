//
//  ProgramSnapshot.swift
//  PowerJack
//
//  The iPhone's running program as it sends it straight to the watch, so a watch that never synced
//  through iCloud can still train at the gym. When they're together the iPhone referees, so the
//  watch makes its copy match this, once the iPhone has every change the watch made.
//

import Foundation
import OSLog
import SwiftData

struct ProgramSnapshot: Codable, Equatable {
    /// The running program, or nil when none runs on the iPhone.
    var program: ProgramState?
    /// The iPhone's other programs, so the watch stops its copy of one the iPhone stopped.
    var notRunning: [UUID]
    /// Every exercise the running program uses.
    var exercises: [ExerciseState]
    /// The latest lift records, so the watch plans strength weeks from them too.
    var strengthLog: StrengthLogState?
    /// The last change from each watch install that the iPhone applied (see `WatchChange.id`).
    var applied: [String: Int]
}

//
// The iPhone's side
//
extension ProgramSnapshot {
    /// Gives rows saved before sync IDs existed their own first, so the watch can match everything sent.
    static func make(in context: ModelContext, applied: [String: Int]) throws -> ProgramSnapshot {
        let programs = try context.fetch(FetchDescriptor<Program>())
        let running = programs.active
        running?.assignSyncIDs()
        if context.hasChanges { try context.save() }

        var exercises: [String: ExerciseState] = [:]
        for workout in running?.programWeeks.flatMap(\.workouts) ?? [] {
            let used = workout.workoutExercises.compactMap(\.exercise) + (workout.nextWeekLayout ?? []).compactMap(\.exercise)
            for exercise in used {
                if let state = exercise.syncState { exercises[state.key] = state }
            }
        }

        return ProgramSnapshot(
            program: running?.syncState,
            notRunning: programs.compactMap(\.syncID).filter { $0 != running?.syncID },
            exercises: exercises.values.sorted { $0.key < $1.key },
            strengthLog: try StrengthLog.latest(in: context)?.syncState,
            applied: applied
        )
    }
}

//
// The watch's side
//
extension ProgramSnapshot {
    /// Makes the watch's copy of the running program match the iPhone's, then saves.
    /// Rows the iPhone no longer has go, unless they hold a logged set.
    func apply(to context: ModelContext) throws {
        let exercises = try applyExercises(in: context)
        let programs = try context.fetch(FetchDescriptor<Program>())

        for program in programs where program.syncID.map(notRunning.contains) == true {
            program.stopForReferee()
        }

        if let state = program {
            let local = Self.match(state, among: programs) ?? {
                let copy = Program(snapshot: state)
                context.insert(copy)
                return copy
            }()
            local.apply(state)
            applyWeeks(state.weeks, to: local, exercises: exercises, in: context)
            // The iPhone referees, so its program is the one running.
            for other in programs where other !== local && other.syncID != state.syncID {
                other.stopForReferee()
            }
        }

        if let strengthLog, try (StrengthLog.latest(in: context)?.date ?? .distantPast) < strengthLog.date {
            context.insert(StrengthLog(snapshot: strengthLog))
        }
        try context.save()
        Logger.sync.debug("Applied the iPhone's program")
    }

    /// The watch's row for the program: the iPhone's own (from iCloud) before a copy, else the only
    /// running program saved before sync IDs, which takes the iPhone's ID.
    private static func match(_ state: ProgramState, among programs: [Program]) -> Program? {
        let same = programs.filter { $0.syncID == state.syncID }
        if let program = same.first(where: { !$0.isFromSnapshot }) ?? same.first { return program }
        let unnumbered = programs.filter { $0.syncID == nil && $0.status == .active }
        return unnumbered.count == 1 ? unnumbered[0] : nil
    }

    private func applyExercises(in context: ModelContext) throws -> [String: Exercise] {
        var byKey: [String: Exercise] = [:]
        for exercise in try context.fetch(FetchDescriptor<Exercise>()) {
            guard let key = exercise.syncKey else { continue }
            // The iPhone's own row, from iCloud, comes before a copy.
            if let found = byKey[key], !found.fromSnapshotValue { continue }
            byKey[key] = exercise
        }
        for state in exercises {
            if let exercise = byKey[state.key] {
                if exercise.fromSnapshotValue { exercise.apply(state) }
            } else {
                let copy = Exercise(snapshot: state)
                context.insert(copy)
                byKey[state.key] = copy
            }
        }
        return byKey
    }

    private func applyWeeks(_ states: [WeekState], to program: Program, exercises: [String: Exercise], in context: ModelContext) {
        Self.sync(
            states, rows: program.programWeeks,
            stateID: \.syncID, rowID: \.syncID, isCopy: \.isFromSnapshot,
            samePlace: { $0.order == $1.order },
            make: { ProgramWeek(snapshot: $0) },
            attach: program.attach,
            update: { week, state in
                week.apply(state)
                applyWorkouts(state.workouts, to: week, exercises: exercises, in: context)
            },
            keeps: { $0.workouts.contains(where: \.hasLoggedSets) },
            remove: { program.detach($0); context.delete($0) }
        )
    }

    private func applyWorkouts(_ states: [WorkoutState], to week: ProgramWeek, exercises: [String: Exercise], in context: ModelContext) {
        Self.sync(
            states, rows: week.workouts,
            stateID: \.syncID, rowID: \.syncID, isCopy: \.isFromSnapshot,
            samePlace: { $0.order == $1.order },
            make: { Workout(snapshot: $0) },
            attach: week.attach,
            update: { workout, state in
                workout.apply(state, exercises: exercises)
                applyExercises(state.exercises, to: workout, exercises: exercises, in: context)
            },
            keeps: \.hasLoggedSets,
            remove: { week.detach($0); context.delete($0) }
        )
    }

    private func applyExercises(_ states: [WorkoutExerciseState], to workout: Workout, exercises: [String: Exercise], in context: ModelContext) {
        Self.sync(
            states, rows: workout.workoutExercises,
            stateID: \.syncID, rowID: \.syncID, isCopy: \.isFromSnapshot,
            samePlace: { $0.order == $1.order && $0.exercise?.syncKey == $1.exerciseKey },
            make: { state in
                guard let exercise = state.exerciseKey.flatMap({ exercises[$0] }) else {
                    Logger.sync.warning("The iPhone's program uses an exercise it didn't send")
                    return nil
                }
                return WorkoutExercise(snapshot: state, exercise: exercise)
            },
            attach: workout.attach,
            update: { workoutExercise, state in
                workoutExercise.apply(state, exercise: state.exerciseKey.flatMap { exercises[$0] })
                Self.sync(
                    state.sets, rows: workoutExercise.workoutSets,
                    stateID: \.syncID, rowID: \.syncID, isCopy: \.isFromSnapshot,
                    samePlace: { $0.order == $1.order && $0.setType.rawValue == $1.setType },
                    make: { WorkoutSet(snapshot: $0) },
                    attach: workoutExercise.attach,
                    update: { $0.apply($1) },
                    keeps: { $0.status == .complete },
                    remove: { workoutExercise.detach($0); context.delete($0) }
                )
            },
            keeps: \.hasLoggedSets,
            remove: { workout.detach($0); context.delete($0) }
        )
    }

    /// Matches each state to a row: one with its sync ID (the iPhone's own before a copy), else the one
    /// row saved before sync IDs in the same place, which takes the ID, else a new row. Rows left over
    /// that the iPhone doesn't have are removed, unless `keeps` holds for them.
    private static func sync<Row: AnyObject, State>(
        _ states: [State],
        rows: [Row],
        stateID: (State) -> UUID,
        rowID: (Row) -> UUID?,
        isCopy: (Row) -> Bool,
        samePlace: (Row, State) -> Bool,
        make: (State) -> Row?,
        attach: (Row) -> Void,
        update: (Row, State) -> Void,
        keeps: (Row) -> Bool,
        remove: (Row) -> Void
    ) {
        var unmatched = rows
        func take(_ matches: (Row) -> Bool) -> Row? {
            unmatched.firstIndex(where: matches).map { unmatched.remove(at: $0) }
        }
        /// A row saved before sync IDs takes one only when nothing else shares its place, so two days
        /// that were already duplicated never swap IDs.
        func unnumbered(in place: State) -> Row? {
            let rows = unmatched.filter { rowID($0) == nil && samePlace($0, place) }
            guard rows.count == 1, states.count(where: { samePlace(rows[0], $0) }) == 1 else { return nil }
            return take { $0 === rows[0] }
        }
        for state in states {
            let id = stateID(state)
            if let row = take({ rowID($0) == id && !isCopy($0) }) ?? take({ rowID($0) == id }) ?? unnumbered(in: state) {
                update(row, state)
            } else if let row = make(state) {
                attach(row)
                update(row, state)
            }
        }
        let sentIDs = Set(states.map(stateID))
        // A second copy of a sent row stays for the tidy-up to fold in.
        for row in unmatched where !(rowID(row).map(sentIDs.contains) ?? false) && !keeps(row) {
            remove(row)
        }
    }
}
