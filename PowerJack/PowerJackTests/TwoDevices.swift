//
//  TwoDevices.swift
//  PowerJackTests
//
//  Two in-memory stores standing in for the iPhone and the watch, linked straight to each other
//  the way WatchConnectivity links them, plus helpers that stand in for iCloud bringing rows over.
//

import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
final class TwoDevices {
    // Held for the whole test, so models stay valid.
    let phone = PowerJackSeed.makeInMemoryContainer()
    let watch = PowerJackSeed.makeInMemoryContainer()
    let referee: PhoneReferee
    let replica: WatchReplica
    /// Where the watch keeps what's pending, as its settings would.
    let replicaDefaults: UserDefaults

    var phoneContext: ModelContext { phone.mainContext }
    var watchContext: ModelContext { watch.mainContext }

    /// An iPhone running a program from the first built-in template of `type`, and a watch that has never synced.
    init(type: TemplateType = .hypertrophy, weeks: Int = 4) throws {
        let suite = "TwoDevices.\(UUID().uuidString)"
        referee = PhoneReferee(defaults: try #require(UserDefaults(suiteName: "\(suite).phone")))
        replicaDefaults = try #require(UserDefaults(suiteName: "\(suite).watch"))
        replica = WatchReplica(defaults: replicaDefaults)

        try ExerciseCatalog.seed(in: phoneContext)
        try TemplateCatalog.seed(in: phoneContext)
        let template = try #require(
            try phoneContext.fetch(FetchDescriptor<TemplateProgram>())
                .filter { $0.templateType == type }
                .min { $0.templateName < $1.templateName }
        )
        let program = Program(programLengthWeeks: weeks, templateProgram: template)
        try phoneContext.insertAndSave(program)
        program.start()
        try phoneContext.save()
    }

    var phoneProgram: Program {
        get throws { try #require(try phoneContext.fetch(FetchDescriptor<Program>()).active) }
    }

    var watchProgram: Program {
        get throws { try #require(try watchContext.fetch(FetchDescriptor<Program>()).active) }
    }

    /// Runs `body` as the watch: what the watch's screens do, with rows and receipts naming the watch.
    func onWatch<T>(together: Bool = true, _ body: (WatchActions) throws -> T) rethrows -> T {
        SyncDevice.current = SyncDevice.watch
        defer { SyncDevice.current = SyncDevice.iPhone }
        return try body(WatchActions(replica: replica, together: together))
    }

    /// The iPhone sends its program straight to the watch.
    @discardableResult
    func sendProgram() throws -> Bool {
        let snapshot = try referee.snapshot(in: phoneContext)
        return try onWatch { _ in try replica.receive(snapshot, in: watchContext) }
    }

    /// The watch sends everything pending; the iPhone applies it and answers with its program.
    @discardableResult
    func sendChanges() throws -> Bool {
        let answer = try referee.receive(replica.pending, in: phoneContext)
        return try onWatch { _ in try replica.receive(answer, in: watchContext) }
    }

    /// The iPhone's row for a set the watch has.
    func onPhone(_ workoutSet: WorkoutSet) throws -> WorkoutSet {
        let id = try #require(workoutSet.syncID)
        return try #require(try phoneContext.fetch(FetchDescriptor<WorkoutSet>()).first { $0.syncID == id && !$0.isFromSnapshot })
    }
}

/// What iCloud brings in: a device's rows, copied into another store with the same sync IDs.
@MainActor
enum ICloud {
    /// Copies `program` into `context` as it is, flagged as the watch's snapshot copies or as the iPhone's own rows.
    @discardableResult
    static func bring(_ program: Program, into context: ModelContext, asSnapshotCopies: Bool) throws -> Program {
        let state = try #require(program.syncState)
        // Exercises come over too, when the store doesn't have them yet.
        let known = Set(try context.fetch(FetchDescriptor<Exercise>()).compactMap(\.syncKey))
        let used = program.programWeeks.flatMap(\.workouts).flatMap(\.workoutExercises).compactMap(\.exercise)
        for exerciseState in Dictionary(used.compactMap { $0.syncState.map { ($0.key, $0) } }, uniquingKeysWith: { first, _ in first }).values
        where !known.contains(exerciseState.key) {
            let exercise = Exercise(snapshot: exerciseState)
            exercise.fromSnapshotValue = asSnapshotCopies
            context.insert(exercise)
        }
        let exercises = Dictionary(
            try context.fetch(FetchDescriptor<Exercise>()).compactMap { exercise in exercise.syncKey.map { ($0, exercise) } },
            uniquingKeysWith: { first, _ in first }
        )
        let copy = Program(snapshot: state)
        copy.fromSnapshotValue = asSnapshotCopies
        context.insert(copy)
        for weekState in state.weeks {
            let week = ProgramWeek(snapshot: weekState)
            week.apply(weekState)
            week.fromSnapshotValue = asSnapshotCopies
            copy.attach(week)
            for workoutState in weekState.workouts {
                week.attach(try workout(workoutState, exercises: exercises, asSnapshotCopy: asSnapshotCopies))
            }
        }
        try context.save()
        return copy
    }

    /// A day built from `state`, as another device would have built it.
    static func workout(_ state: WorkoutState, exercises: [String: Exercise], asSnapshotCopy: Bool) throws -> Workout {
        let workout = Workout(snapshot: state)
        workout.apply(state, exercises: exercises)
        workout.fromSnapshotValue = asSnapshotCopy
        for exerciseState in state.exercises {
            let exercise = try #require(exerciseState.exerciseKey.flatMap { exercises[$0] })
            let workoutExercise = WorkoutExercise(snapshot: exerciseState, exercise: exercise)
            workoutExercise.apply(exerciseState, exercise: exercise)
            workoutExercise.fromSnapshotValue = asSnapshotCopy
            workout.attach(workoutExercise)
            for setState in exerciseState.sets {
                let workoutSet = WorkoutSet(snapshot: setState)
                workoutSet.fromSnapshotValue = asSnapshotCopy
                workoutExercise.attach(workoutSet)
            }
        }
        return workout
    }

    /// `state` with new sync IDs throughout, as when another device planned the same day itself.
    static func renumbered(_ state: WorkoutState) -> WorkoutState {
        var state = state
        state.syncID = UUID()
        state.exercises = state.exercises.map { exercise in
            var exercise = exercise
            exercise.syncID = UUID()
            exercise.sets = exercise.sets.map { set in
                var set = set
                set.syncID = UUID()
                return set
            }
            return exercise
        }
        return state
    }
}

/// A watch workout: started, with every set logged at `weight` and its feedback answered.
@MainActor
extension WatchActions {
    func train(_ workout: Workout, in program: Program, weight: Double = 100, at date: Date = .now) {
        start(workout, in: program, at: date)
        for workoutExercise in workout.workoutExercises {
            if workoutExercise.checkInPending {
                resolveCheckIn(of: workoutExercise, with: .continue)
            }
            var logged = 0
            while let workoutSet = workoutExercise.nextSet, logged < 20 {
                var entry = SetEntry(for: workoutSet, unit: .pounds)
                if entry.weightTenthsPounds == nil { entry.weight = weight }
                log(entry, on: workoutSet, of: workoutExercise, at: date.addingTimeInterval(Double(logged + 1) * 60))
                logged += 1
            }
            if workoutExercise.needsFeedback {
                let feedback = workoutExercise.templateType?.ratesRepsInReserve == true
                    ? ExerciseFeedback(repsInReserve: .two, levelOfPain: .none)
                    : ExerciseFeedback(levelOfEffort: .challenge, levelOfPain: .none)
                rate(workoutExercise, feedback: feedback, topSet: workoutExercise.topSetsNeedRating ? .two : nil)
            }
        }
        finish(workout, in: program)
    }
}
