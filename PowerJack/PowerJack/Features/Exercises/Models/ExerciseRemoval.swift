//
//  ExerciseRemoval.swift
//  PowerJack
//
//  Removing the lifter's own exercise without losing what they logged:
//  - one nothing uses is deleted,
//  - one with history is archived (hidden from search and pickers, history kept),
//  - or merged into another exercise, which takes every row, set and saved record, then it's deleted.
//  Built-in exercises are never removed.
//

import Foundation
import OSLog
import SwiftData

@MainActor
enum ExerciseRemoval {
    /// What uses an exercise, so the lifter knows what a removal touches.
    struct Usage: Equatable {
        /// Logged sets in programs, imports and saved history, counted the way charts count them.
        var loggedSets = 0
        /// True when a template, program, import or saved history still names it.
        var isUsed = false
    }

    enum RemovalError: LocalizedError {
        case builtIn
        case used
        case sameExercise

        var errorDescription: String? {
            switch self {
            case .builtIn: "Built-in exercises can't be removed."
            case .used: "This exercise has history. Archive it or merge it instead."
            case .sameExercise: "Choose a different exercise to merge into."
            }
        }
    }

    // MARK: Usage

    static func usage(of exercise: Exercise, in context: ModelContext) throws -> Usage {
        let keys = historyKeys(of: exercise)
        var usage = Usage()

        let rows = exercise.workoutExercisesValue ?? []
        let substituted = exercise.substitutedWorkoutExercisesValue ?? []
        // What was actually done as this exercise: its own rows without a substitute, and rows it stood in on.
        for row in rows where row.substitute == nil {
            usage.loggedSets += row.workoutSets.count { $0.status == .complete }
        }
        for row in substituted {
            usage.loggedSets += row.workoutSets.count { $0.status == .complete }
        }

        let imported = try importedSets(of: keys, in: context)
        usage.loggedSets += imported.count

        // Saved history of programs that no longer exist. Live programs were counted above.
        let live = Set(try context.fetch(FetchDescriptor<Program>()).compactMap(\.syncID))
        let archived = HistoryArchive.uniqueBatchRecords(try HistoryArchive.archivedRows(excluding: live, in: context))
        usage.loggedSets += archived.count { keys.contains($0.row.exerciseKey) && $0.row.setStatus.lowercased() == Status.complete.rawValue }

        let savedRows = try context.fetchCount(FetchDescriptor<HistoryExercise>(predicate: #Predicate { keys.contains($0.exerciseKeyValue) }))
            + context.fetchCount(FetchDescriptor<HistoryRecord>(predicate: #Predicate { keys.contains($0.exerciseKeyValue) }))
        usage.isUsed = !(exercise.templateExercisesValue ?? []).isEmpty || !rows.isEmpty || !substituted.isEmpty
            || !imported.isEmpty || savedRows > 0
        return usage
    }

    // MARK: Delete

    /// Deletes an own exercise nothing uses. Anything with history has to be archived or merged.
    static func delete(_ exercise: Exercise, in context: ModelContext) throws {
        guard exercise.userCreated else { throw RemovalError.builtIn }
        guard try !usage(of: exercise, in: context).isUsed else { throw RemovalError.used }
        let name = exercise.traceName
        try saveAsOne(in: context) { context.delete(exercise) }
        TraceLog.record(.data, "Deleted \(name)")
    }

    // MARK: Archive

    static func archive(_ exercise: Exercise, in context: ModelContext, at date: Date = .now) throws {
        guard exercise.userCreated else { throw RemovalError.builtIn }
        guard !exercise.isArchived else { return }
        try saveAsOne(in: context) { exercise.archivedAtValue = date }
        TraceLog.record(.data, "Archived \(exercise.traceName)")
    }

    static func unarchive(_ exercise: Exercise, in context: ModelContext) throws {
        guard exercise.isArchived else { return }
        try saveAsOne(in: context) { exercise.archivedAtValue = nil }
        TraceLog.record(.data, "Unarchived \(exercise.traceName)")
    }

    // MARK: Merge

    /// Moves everything of `source` to `target` and deletes `source`, in one save. When the save
    /// fails nothing changes. Starred and saved charts follow on this device once it saved.
    /// - Returns: How many logged sets moved.
    @discardableResult
    static func merge(_ source: Exercise, into target: Exercise, in context: ModelContext,
                      defaults: UserDefaults = .standard) throws -> Int {
        guard source.userCreated else { throw RemovalError.builtIn }
        guard source !== target else { throw RemovalError.sameExercise }
        let moved = try usage(of: source, in: context).loggedSets
        let oldKeys = historyKeys(of: source)
        let sourceName = source.traceName

        try saveAsOne(in: context) {
            // Saved history names exercises by key, so an own target needs its sync ID first.
            target.assignSyncID()

            for row in source.templateExercisesValue ?? [] {
                row.exercise = target
            }
            for row in source.workoutExercisesValue ?? [] {
                row.mergeExercise(into: target)
            }
            for row in source.substitutedWorkoutExercisesValue ?? [] {
                row.mergeSubstitute(into: target)
            }

            try moveHistory(from: oldKeys, strengthKey: StrengthLifts.key(for: source), to: target, in: context)
            context.delete(source)
        }

        let newKey = target.syncKey ?? target.exerciseName
        StudyOptions.replaceExercise(oldKeys, with: newKey, in: defaults)
        TraceLog.record(.data, "Merged \(sourceName) into \(target.traceName), \(moved) logged sets")
        return moved
    }

    // MARK: Helpers

    /// Points imports, saved history and the lift record that named an exercise by `oldKeys` (and
    /// `strengthKey`) at `target`. Doesn't save. Charts follow with `StudyOptions.replaceExercise` once saved.
    static func moveHistory(from oldKeys: [String], strengthKey: String, to target: Exercise, in context: ModelContext) throws {
        let newKey = target.syncKey ?? target.exerciseName
        for set in try importedSets(of: oldKeys, in: context) {
            set.exerciseKey = newKey
            set.exerciseName = target.exerciseName
            set.muscle = target.primaryMuscleFocus.rawValue
        }
        let saved = SavedExercise(target, key: newKey)
        for slot in try context.fetch(FetchDescriptor<HistoryExercise>(predicate: #Predicate { oldKeys.contains($0.exerciseKeyValue) })) {
            slot.exerciseKeyValue = saved.key
            slot.exerciseNameValue = saved.name
            slot.exerciseSourceValue = saved.source
            slot.equipmentValue = saved.equipment
            slot.primaryMuscleValue = saved.primaryMuscle
        }
        for record in try context.fetch(FetchDescriptor<HistoryRecord>(predicate: #Predicate { oldKeys.contains($0.exerciseKeyValue) })) {
            record.exerciseKeyValue = saved.key
            record.exerciseNameValue = saved.name
            record.exerciseSourceValue = saved.source
            record.equipmentValue = saved.equipment
            record.primaryMuscleValue = saved.primaryMuscle
        }
        try moveStrengthRecord(from: strengthKey, to: target, in: context)
    }

    /// The keys saved history and imports name an exercise by: its sync key, or its name for rows
    /// saved before it had one.
    static func historyKeys(of exercise: Exercise) -> [String] {
        [exercise.syncKey, exercise.exerciseName].compactMap(\.self).filter { !$0.isEmpty }
    }

    private static func importedSets(of keys: [String], in context: ModelContext) throws -> [ImportedSet] {
        try context.fetch(FetchDescriptor<ImportedSet>(predicate: #Predicate { keys.contains($0.exerciseKey) }))
    }

    /// The target keeps its own lift record. One that never had one takes the source's, so a
    /// strength program doesn't start it over. Lift records are only ever added, so a new log holds it.
    private static func moveStrengthRecord(from sourceKey: String, to target: Exercise, in context: ModelContext) throws {
        guard var state = try StrengthLog.latest(in: context)?.state else { return }
        let targetKey = StrengthLifts.key(for: target)
        guard sourceKey != targetKey, let record = state.lifts.removeValue(forKey: sourceKey) else { return }
        if state.lifts[targetKey] == nil { state.lifts[targetKey] = record }
        context.insert(StrengthLog(date: .now, state: state))
        try StrengthLog.rotate(in: context)
    }

    /// Saves what's pending first, so a failed change rolls back only itself.
    private static func saveAsOne(in context: ModelContext, _ change: () throws -> Void) throws {
        if context.hasChanges { try context.save() }
        do {
            try change()
            try context.save()
        } catch {
            context.rollback()
            Logger.persistence.error("Could not remove an exercise: \(error.localizedDescription)")
            throw error
        }
    }

    /// How saved history names an exercise, as the export writes it.
    private struct SavedExercise {
        let key: String
        let name: String
        let source: String
        let equipment: String
        let primaryMuscle: String

        init(_ exercise: Exercise, key: String) {
            self.key = key
            name = exercise.exerciseName
            source = exercise.userCreated ? "Custom" : "Built-in"
            equipment = exercise.equipment.displayName
            primaryMuscle = exercise.primaryMuscleFocus.rawValue.capitalized
        }
    }
}

extension WorkoutExercise {
    /// Plans `target` where this row planned the merged exercise. A substitute that is now the
    /// planned exercise itself is no substitute any more.
    func mergeExercise(into target: Exercise) {
        replaceDuplicateExercise(with: target)
        if substitute === target { substituteValue = nil }
    }

    func mergeSubstitute(into target: Exercise) {
        substituteValue = exercise === target ? nil : target
    }
}
