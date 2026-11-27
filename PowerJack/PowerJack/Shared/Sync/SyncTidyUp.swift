//
//  SyncTidyUp.swift
//  PowerJack
//
//  Cleans up what syncing the iPhone and the watch can leave behind. It runs after every iCloud
//  import and every direct sync, on both devices, and decides the same way on both, so they
//  never delete different copies. A row with a logged set is only ever folded into another copy
//  of itself, never just deleted, and every log also lives on in its `SetReceipt`.
//
//  Syncing only brings copies of what was planned or logged lately, so after the first run on a store
//  a run looks only at the running program and the last `receiptWindow`, not years of history.
//

import Foundation
import OSLog
import SwiftData

enum SyncTidyUp {
    /// How far back receipts are checked. A device that syncs late is still caught up.
    static let receiptWindow: TimeInterval = 30 * 24 * 60 * 60

    /// How much of the store a run looks through.
    enum Scope {
        /// Every program's days and every log.
        case everything
        /// The running program's days, and the days and logs of the last `receiptWindow`: all that
        /// syncing can still bring copies of. The first run on a store looks through everything.
        case recent
    }

    /// What started the current run, for the trace.
    private static var trigger = "sync"

    /// The store the last run that looked through everything tidied.
    private static weak var tidiedInFull: ModelContainer?

    /// - Parameter running: on the watch, the program the iPhone last said is running.
    /// - Parameter trigger: what started it, for the trace, like "iCloud import" or "watch changes".
    /// - Returns: Whether anything changed. Changes are saved.
    @discardableResult
    static func run(in context: ModelContext, running: UUID? = nil, now: Date = .now, trigger: String = "sync", scope: Scope = .everything) throws -> Bool {
        self.trigger = trigger
        let recent = now.addingTimeInterval(-receiptWindow)
        let inFull = scope == .everything || tidiedInFull !== context.container
        let since = inFull ? nil : recent
        var changed = try mergeSnapshotCopies(in: context)
        changed = try mergeOwnExercises(in: context) || changed
        changed = try mergeDuplicateDays(in: context, since: since) || changed
        changed = try mergeDuplicateLogs(in: context, since: since ?? .distantPast) || changed
        changed = try keepOneRunningProgram(in: context, running: running) || changed
        changed = try showLatestLogs(in: context, since: recent) || changed
        if changed {
            try context.save()
            Logger.sync.info("Tidied up after syncing")
        }
        if inFull { tidiedInFull = context.container }
        return changed
    }

    // MARK: Snapshot copies

    /// The watch's copy of a row, made from the iPhone's snapshot, folds into the iPhone's own row
    /// once iCloud brings it. Top down, so a copied program takes its copied weeks with it.
    private static func mergeSnapshotCopies(in context: ModelContext) throws -> Bool {
        let copies = try Program.fromSnapshot(in: context)
        let programs = copies.isEmpty ? [] : try context.fetch(FetchDescriptor<Program>())
        var changed = try fold(copies, in: context) { copy in
            programs.first { $0 !== copy && !$0.isFromSnapshot && $0.syncID == copy.syncID }
        } merge: { $0.merge($1) }

        changed = try fold(try ProgramWeek.fromSnapshot(in: context), in: context) { copy in
            copy.programValue?.programWeeks.first { $0 !== copy && !$0.isFromSnapshot && $0.syncID == copy.syncID }
        } merge: { $0.merge($1) } || changed

        changed = try fold(try Workout.fromSnapshot(in: context), in: context) { copy in
            copy.programWeekValue?.workouts.first { $0 !== copy && !$0.isFromSnapshot && $0.syncID == copy.syncID }
        } merge: { $0.merge($1, matching: .syncID) } || changed

        changed = try fold(try WorkoutExercise.fromSnapshot(in: context), in: context) { copy in
            copy.workoutValue?.workoutExercises.first { $0 !== copy && !$0.isFromSnapshot && $0.syncID == copy.syncID }
        } merge: { $0.merge($1, matching: .syncID) } || changed

        changed = try fold(try WorkoutSet.fromSnapshot(in: context), in: context) { copy in
            copy.workoutExerciseValue?.workoutSets.first { $0 !== copy && !$0.isFromSnapshot && $0.syncID == copy.syncID }
        } merge: { $0.merge($1) } || changed
        return changed
    }

    private static func fold<Row: PersistentModel>(
        _ copies: [Row],
        in context: ModelContext,
        original: (Row) -> Row?,
        merge: (Row, Row) -> Void
    ) throws -> Bool {
        var changed = false
        for copy in copies where !copy.isDeleted {
            guard let original = original(copy) else { continue }
            let logged = loggedSets(in: copy)
            merge(original, copy)
            context.delete(copy)
            trace("folded the watch's \(Row.self) copy \(TraceLog.id(syncID(of: copy))) into the iPhone's row, \(logged) logged sets")
            changed = true
        }
        // Saved now, so the next level down no longer sees the rows this one deleted.
        if changed { try context.save() }
        return changed
    }

    /// The lifter's own exercises the watch copied fold into the iPhone's rows. Built-in ones are
    /// tidied by `ExerciseCatalog.removeDuplicates`, which keeps the iPhone's older row.
    private static func mergeOwnExercises(in context: ModelContext) throws -> Bool {
        let own = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.catalogID == nil && $0.syncIDValue != nil }))
        var changed = false
        for copies in Dictionary(grouping: own, by: \.syncIDValue).values where copies.count > 1 {
            let ranked = copies.sorted { ($0.fromSnapshotValue ? 1 : 0, $0.createdAtValue) < ($1.fromSnapshotValue ? 1 : 0, $1.createdAtValue) }
            let survivor = ranked[0]
            // Two of the iPhone's own rows can't share an ID, so a tie means two watch copies: keep both.
            guard survivor.fromSnapshotValue != ranked[1].fromSnapshotValue || survivor.createdAtValue != ranked[1].createdAtValue else { continue }
            for duplicate in ranked.dropFirst() {
                survivor.takeOverRows(of: duplicate)
                context.delete(duplicate)
            }
            trace("kept \(survivor.traceName), deleted \(ranked.count - 1) copies")
            changed = true
        }
        return changed
    }

    // MARK: Duplicate days

    /// A day planned on both devices while they were apart shows up twice in its week once iCloud
    /// brings both. One stays (see `ranksFirst`) and the other folds into it by place, so its logged
    /// sets move over, the later log winning where both logged the same set. Whichever copy was
    /// logged, the day keeps every log.
    /// - Parameter since: when set, only the running program's weeks and weeks with a day planned since then.
    private static func mergeDuplicateDays(in context: ModelContext, since: Date?) throws -> Bool {
        var changed = false
        for week in try weeks(in: context, since: since) {
            for days in Dictionary(grouping: week.workouts, by: \.order).values where days.count > 1 {
                guard let keep = first(of: days, by: { ranksFirst($0, over: $1) }) else { continue }
                for day in days where day !== keep {
                    trace("kept day \(TraceLog.id(keep.syncID)), folded in day \(TraceLog.id(day.syncID)) with \(loggedSets(in: day)) logged sets")
                    keep.merge(day, matching: .place)
                    week.detach(day)
                    context.delete(day)
                }
                changed = true
            }
        }
        return changed
    }

    private static func weeks(in context: ModelContext, since: Date?) throws -> [ProgramWeek] {
        guard let since else { return try context.fetch(FetchDescriptor<ProgramWeek>()) }
        let running = try context.fetch(FetchDescriptor<Program>()).filter { $0.status == .active }.flatMap(\.programWeeks)
        let planned = try Workout.planned(since: since, in: context).compactMap(\.programWeekValue)
        var seen = Set<PersistentIdentifier>()
        return (running + planned).filter { seen.insert($0.persistentModelID).inserted }
    }

    /// Whether day `a` stays over day `b`: the iPhone's, else the older. It's decided only from what
    /// never changes, not from what's logged, so both devices pick the same copy however far their
    /// syncing has got and never delete one each. Nil when nothing tells them apart.
    static func ranksFirst(_ a: Workout, over b: Workout) -> Bool? {
        if (a.createdOn == SyncDevice.iPhone) != (b.createdOn == SyncDevice.iPhone) { return a.createdOn == SyncDevice.iPhone }
        let aCreated = a.createdAt ?? .distantPast, bCreated = b.createdAt ?? .distantPast
        if aCreated != bCreated { return aCreated < bCreated }
        guard let aID = a.syncID?.uuidString, let bID = b.syncID?.uuidString, aID != bID else { return nil }
        return aID < bID
    }

    // MARK: History

    /// The same workout finished on both devices apart writes two volume logs, and a week closed on
    /// both writes two strength logs. The latest stays, like the day's sets. Logs written at the very
    /// same moment can't be told apart, so both stay.
    private static func mergeDuplicateLogs(in context: ModelContext, since: Date) throws -> Bool {
        var changed = false
        for logs in Dictionary(grouping: try WorkoutLog.withSession(since: since, in: context), by: \.sessionID).values where logs.count > 1 {
            let latest = logs.map(\.date).max()
            for log in logs where log.date != latest {
                context.delete(log)
                changed = true
            }
            trace("kept the latest volume log of workout \(TraceLog.id(logs.first?.sessionID)), \(logs.count) in all")
        }
        for logs in Dictionary(grouping: try StrengthLog.withSession(since: since, in: context), by: \.sessionID).values where logs.count > 1 {
            let latest = logs.map(\.date).max()
            for log in logs where log.date != latest {
                context.delete(log)
                changed = true
            }
            trace("kept the latest strength log of week \(TraceLog.id(logs.first?.sessionID)), \(logs.count) in all")
        }
        return changed
    }

    // MARK: Running program

    /// Only one program runs. When syncing leaves two, the iPhone keeps the one with logged workouts
    /// (the latest logged when both have) and stops the other, never deleting it. Only the iPhone
    /// decides, so the two devices never stop one each: the watch follows the one the iPhone said.
    private static func keepOneRunningProgram(in context: ModelContext, running: UUID?) throws -> Bool {
        let active = try context.fetch(FetchDescriptor<Program>()).filter { $0.status == .active }
        guard active.count > 1 else { return false }
        let keep: Program?
        if SyncDevice.current == SyncDevice.iPhone {
            keep = first(of: active, by: { programRanksFirst($0, over: $1) })
        } else {
            keep = running.flatMap { id in active.first { $0.syncID == id } }
        }
        guard let keep else { return false }
        for program in active where program !== keep {
            trace("kept program \(TraceLog.id(keep.syncID)) running, stopped \(TraceLog.id(program.syncID))")
            program.stop()
            program.stopAndCascade()
        }
        Logger.sync.info("Stopped a second running program after syncing")
        return true
    }

    static func programRanksFirst(_ a: Program, over b: Program) -> Bool? {
        if a.hasLoggedSets != b.hasLoggedSets { return a.hasLoggedSets }
        if let aLogged = a.lastLoggedAt, let bLogged = b.lastLoggedAt, aLogged != bLogged { return aLogged > bLogged }
        guard let aID = a.syncID?.uuidString, let bID = b.syncID?.uuidString, aID != bID else { return nil }
        return aID < bID
    }

    // MARK: Receipts

    /// An older upload can overwrite a set through iCloud. Each logged set shows its latest receipt,
    /// judged by when it was logged, so a device syncing a day late never wins over newer logs.
    private static func showLatestLogs(in context: ModelContext, since date: Date) throws -> Bool {
        let receipts = try SetReceipt.written(since: date, in: context)
        guard !receipts.isEmpty else { return false }
        let latestBySet = Dictionary(grouping: receipts, by: \.setID).compactMapValues { SetReferee.latest($0.map(\.log)) }
        var shown = 0
        for workoutSet in try WorkoutSet.logged(since: date, in: context) {
            guard let latest = workoutSet.syncID.flatMap({ latestBySet[$0] }) else { continue }
            if workoutSet.showLatest(latest) { shown += 1 }
        }
        if shown > 0 { trace("showed the latest log on \(shown) sets") }
        return shown > 0
    }

    // MARK: Helpers

    private static func trace(_ action: String) {
        TraceLog.record(.data, "Tidy-up (\(trigger)): \(action)")
    }

    private static func syncID(of row: any PersistentModel) -> UUID? {
        switch row {
        case let program as Program: program.syncID
        case let week as ProgramWeek: week.syncID
        case let workout as Workout: workout.syncID
        case let workoutExercise as WorkoutExercise: workoutExercise.syncID
        case let workoutSet as WorkoutSet: workoutSet.syncID
        default: nil
        }
    }

    /// Logged sets in a row and the rows under it.
    private static func loggedSets(in row: any PersistentModel) -> Int {
        let sets: [WorkoutSet] = switch row {
        case let program as Program: program.programWeeks.flatMap(\.workouts).flatMap(\.workoutExercises).flatMap(\.workoutSets)
        case let week as ProgramWeek: week.workouts.flatMap(\.workoutExercises).flatMap(\.workoutSets)
        case let workout as Workout: workout.workoutExercises.flatMap(\.workoutSets)
        case let workoutExercise as WorkoutExercise: workoutExercise.workoutSets
        case let workoutSet as WorkoutSet: [workoutSet]
        default: []
        }
        return sets.filter { $0.status == .complete }.count
    }

    /// The row that ranks first over every other, or nil when two can't be told apart.
    private static func first<Row: AnyObject>(of rows: [Row], by ranksFirst: (Row, Row) -> Bool?) -> Row? {
        guard var best = rows.first else { return nil }
        for row in rows.dropFirst() {
            guard let bestStays = ranksFirst(best, row) else { return nil }
            if !bestStays { best = row }
        }
        return best
    }
}
