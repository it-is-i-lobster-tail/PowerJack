//
//  HistoryArchive.swift
//  PowerJack
//
//  Saves the sets of programs that ended, so they outlive the program: as `HistoryRecord` rows and,
//  in the leaner shape, as `HistoryProgram` and `HistoryExercise` rows (see HistoryShape.swift).
//  Reads prefer the lean shape and fall back to `HistoryRecord` for a batch saved before it.
//  Only the iPhone saves them; the watch only gets them through iCloud.
//

import Foundation
import OSLog
import SwiftData

enum HistoryArchive {
    /// Saves every set of `program` once, with `status` in place of the program's own when given.
    /// A program that never started a workout has nothing worth keeping.
    /// - Returns: Whether rows were added.
    @discardableResult
    static func save(_ program: Program, as status: HistoryProgramStatus? = nil, in context: ModelContext, at date: Date = .now) throws -> Bool {
        // Checked first: every launch passes every ended program here, and most are saved already.
        // Finding out whether one trained walks all its sets.
        if let programID = program.syncID, try isSaved(programID, in: context) { return false }
        guard hasTrained(program) else { return false }
        // A program without sync IDs yet can't have saved rows.
        if program.syncID == nil { program.assignSyncIDs() }
        guard let programID = program.syncID else { return false }

        let batchID = UUID()
        let started = HistoryExport.firstActivity(of: program)
        let rows = HistoryExport.rows(for: program, status: status)
        for (order, row) in rows.enumerated() {
            context.insert(HistoryRecord(row, batchID: batchID, savedAt: date, programStarted: started, order: order))
        }
        insertLean(rows, batchID: batchID, savedAt: date, programStarted: started, in: context)
        Logger.persistence.info("Saved a program's history")
        return true
    }

    /// Old versions didn't keep start times, so a finished program or a logged set counts too.
    private static func hasTrained(_ program: Program) -> Bool {
        program.status == .complete
            || program.hasLoggedSets
            || program.programWeeks.contains { $0.workouts.contains { $0.startedAt != nil } }
    }

    /// Call right before deleting `program`: its saved rows are marked deleted, or saved that way.
    static func programWillBeDeleted(_ program: Program, in context: ModelContext) throws {
        // The running program can't be deleted.
        guard program.status != .active else { return }
        if let programID = program.syncID {
            let saved = try records(of: programID, in: context)
            let lean = try programs(of: programID, in: context)
            if !saved.isEmpty || !lean.isEmpty {
                saved.forEach { $0.markDeleted() }
                lean.forEach { $0.markDeleted() }
                return
            }
        }
        try save(program, as: .deleted, in: context)
    }

    /// Saves every ended program that isn't saved yet, then saves the store. After an update
    /// this keeps all the history from before the long view existed.
    static func saveEndedPrograms(in context: ModelContext) throws {
        let ended = try context.fetch(FetchDescriptor<Program>()).filter { program in
            !program.isFromSnapshot && [.complete, .stopped, .skipped].contains(program.status)
        }
        var added = false
        for program in ended {
            added = try save(program, in: context) || added
        }
        if added { try context.save() }
    }

    /// The saved rows, one batch per program, in program order. Two iPhones can each save the
    /// same program before iCloud brings the other's rows, so the first batch saved wins.
    static func records(in context: ModelContext) throws -> [ArchivedRow] {
        uniqueBatchRecords(archivedRows(
            programs: try context.fetch(FetchDescriptor<HistoryProgram>()),
            exercises: try context.fetch(FetchDescriptor<HistoryExercise>()),
            legacy: try context.fetch(FetchDescriptor<HistoryRecord>())
        ))
    }

    /// Every saved row, in order: a batch from its lean rows when it has them, else from its
    /// `HistoryRecord` rows. When two iPhones both wrote a batch's lean rows, one copy is kept,
    /// the same on every device.
    static func archivedRows(programs: [HistoryProgram], exercises: [HistoryExercise], legacy: [HistoryRecord]) -> [ArchivedRow] {
        var copies: [UUID: HistoryProgram] = [:]
        for program in programs {
            guard let batchID = program.batchID else { continue }
            if let kept = copies[batchID], (kept.copyID?.uuidString ?? "") <= (program.copyID?.uuidString ?? "") { continue }
            copies[batchID] = program
        }
        let exercisesByCopy = Dictionary(grouping: exercises, by: \.copyID)
        var rows = copies.values.flatMap { program in
            program.archivedRows(exercisesByCopy[program.copyID] ?? [])
        }
        rows += legacy.filter { record in record.batchID.map { copies[$0] == nil } ?? true }.map(\.archived)
        return rows.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }

    static func uniqueBatchRecords(_ all: [ArchivedRow]) -> [ArchivedRow] {
        var kept: [UUID?: (batchID: UUID?, savedAt: Date)] = [:]
        for record in all {
            let key = record.programID ?? record.batchID
            if let current = kept[key], !isEarlier(record, than: current) { continue }
            kept[key] = (record.batchID, record.savedAt)
        }
        return all.filter { kept[$0.programID ?? $0.batchID]?.batchID == $0.batchID }
    }

    private static func isEarlier(_ record: ArchivedRow, than kept: (batchID: UUID?, savedAt: Date)) -> Bool {
        if record.savedAt != kept.savedAt { return record.savedAt < kept.savedAt }
        return (record.batchID?.uuidString ?? "") < (kept.batchID?.uuidString ?? "")
    }

    /// A set fixed after its program ended: the rows saved for it show the fix too.
    static func correct(_ workoutSet: WorkoutSet, in context: ModelContext) throws {
        guard
            let workoutExercise = workoutSet.workoutExerciseValue,
            let workout = workoutExercise.workoutValue,
            let week = workout.programWeekValue,
            let program = week.programValue,
            let programID = program.syncID,
            let weekIndex = program.programWeeks.firstIndex(where: { $0 === week }),
            let dayIndex = week.workouts.firstIndex(where: { $0 === workout }),
            let exerciseIndex = workout.workoutExercises.firstIndex(where: { $0 === workoutExercise })
        else { return }

        // Found the way the export numbered the row when the program ended.
        let id: UUID? = programID
        let (weekNumber, day, exerciseNumber) = (weekIndex + 1, dayIndex + 1, exerciseIndex + 1)
        let setNumber = workoutExercise.number(of: workoutSet)
        let setType = HistoryExport.setType(of: workoutSet, in: workoutExercise)
        let descriptor = FetchDescriptor<HistoryRecord>(predicate: #Predicate {
            $0.programIDValue == id && $0.weekValue == weekNumber && $0.dayValue == day
                && $0.exerciseNumberValue == exerciseNumber && $0.setNumberValue == setNumber
        })
        for record in try context.fetch(descriptor) where record.setTypeValue == setType {
            record.correct(reps: workoutSet.reps, weightTenthsPounds: workoutSet.weightTenthsPounds)
        }
        let slots = FetchDescriptor<HistoryExercise>(predicate: #Predicate {
            $0.programIDValue == id && $0.weekValue == weekNumber && $0.dayValue == day && $0.exerciseNumberValue == exerciseNumber
        })
        for slot in try context.fetch(slots) {
            slot.correct(setNumber: setNumber, setType: setType, reps: workoutSet.reps, weightTenthsPounds: workoutSet.weightTenthsPounds)
        }
    }

    // MARK: Lean shape

    private static func insertLean(_ rows: [HistoryRow], batchID: UUID, savedAt: Date, programStarted: Date?, in context: ModelContext) {
        guard let lean = HistoryProgram.make(from: rows, batchID: batchID, savedAt: savedAt, programStarted: programStarted) else { return }
        context.insert(lean.program)
        lean.exercises.forEach(context.insert)
    }

    /// Writes the lean rows of every `HistoryRecord` batch that has none yet, then saves. A batch whose
    /// lean rows wouldn't read back exactly the same is left on its old rows, which reads still use.
    /// - Returns: How many batches were written.
    @discardableResult
    static func backfillLeanHistory(in context: ModelContext) throws -> Int {
        var done = Set(try context.fetch(FetchDescriptor<HistoryProgram>()).compactMap(\.batchID))
        var batchIDs = FetchDescriptor<HistoryRecord>()
        batchIDs.propertiesToFetch = [\.batchIDValue]
        let missing = Set(try context.fetch(batchIDs).compactMap(\.batchID)).subtracting(done)
        var written = 0
        for batchID in missing {
            let id: UUID? = batchID
            let records = try context.fetch(FetchDescriptor<HistoryRecord>(
                predicate: #Predicate { $0.batchIDValue == id }, sortBy: [SortDescriptor(\.orderValue)]
            ))
            guard let first = records.first,
                  let lean = HistoryProgram.make(
                      from: records.map(\.row), batchID: batchID, savedAt: first.savedAt, programStarted: first.programStartedValue
                  )
            else { continue }
            let expected = records.enumerated().map { order, record in
                ArchivedRow(row: record.row, batchID: batchID, savedAt: first.savedAt, programStarted: first.programStarted, order: order)
            }
            let sameBatch = records.allSatisfy { $0.savedAt == first.savedAt && $0.programStartedValue == first.programStartedValue }
            guard sameBatch, lean.program.archivedRows(lean.exercises) == expected else {
                Logger.persistence.error("Kept a history batch on its old rows: they don't fit the lean shape")
                continue
            }
            context.insert(lean.program)
            lean.exercises.forEach(context.insert)
            done.insert(batchID)
            written += 1
        }
        if written > 0 {
            try context.save()
            Logger.persistence.info("Wrote the lean history of \(written) saved programs")
        }
        return written
    }

    /// Whether either shape holds rows for the program.
    private static func isSaved(_ programID: UUID, in context: ModelContext) throws -> Bool {
        try !records(of: programID, in: context, limit: 1).isEmpty || !programs(of: programID, in: context, limit: 1).isEmpty
    }

    private static func programs(of programID: UUID, in context: ModelContext, limit: Int? = nil) throws -> [HistoryProgram] {
        let id: UUID? = programID
        var descriptor = FetchDescriptor<HistoryProgram>(predicate: #Predicate { $0.programIDValue == id })
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    private static func records(of programID: UUID, in context: ModelContext, limit: Int? = nil) throws -> [HistoryRecord] {
        let id: UUID? = programID
        var descriptor = FetchDescriptor<HistoryRecord>(predicate: #Predicate { $0.programIDValue == id })
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }
}

extension Program {
    /// Keeps the ended program's sets in the long history. A failure only logs, because the
    /// export and the next launch save any ended program still missing.
    func saveHistory() {
        guard let modelContext else { return }
        do {
            try HistoryArchive.save(self, in: modelContext)
        } catch {
            Logger.persistence.error("Could not save a program's history: \(error.localizedDescription)")
        }
    }
}
