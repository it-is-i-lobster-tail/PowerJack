//
//  HistoryArchive.swift
//  PowerJack
//
//  Saves the sets of programs that ended as `HistoryRecord` rows, so they outlive the program.
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
        guard hasTrained(program) else { return false }
        if program.syncID == nil { program.assignSyncIDs() }
        guard let programID = program.syncID, try records(of: programID, in: context, limit: 1).isEmpty else { return false }

        let batchID = UUID()
        let started = HistoryExport.firstActivity(of: program)
        for (order, row) in HistoryExport.rows(for: program, status: status).enumerated() {
            context.insert(HistoryRecord(row, batchID: batchID, savedAt: date, programStarted: started, order: order))
        }
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
            if !saved.isEmpty {
                saved.forEach { $0.markDeleted() }
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
    static func records(in context: ModelContext) throws -> [HistoryRecord] {
        let all = try context.fetch(FetchDescriptor<HistoryRecord>(sortBy: [SortDescriptor(\.orderValue)]))
        var kept: [UUID?: (batchID: UUID?, savedAt: Date)] = [:]
        for record in all {
            let key = record.programID ?? record.batchID
            if let current = kept[key], !isEarlier(record, than: current) { continue }
            kept[key] = (record.batchID, record.savedAt)
        }
        return all.filter { kept[$0.programID ?? $0.batchID]?.batchID == $0.batchID }
    }

    private static func isEarlier(_ record: HistoryRecord, than kept: (batchID: UUID?, savedAt: Date)) -> Bool {
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
