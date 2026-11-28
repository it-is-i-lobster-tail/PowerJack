//
//  ExerciseCatalog+SameName.swift
//  PowerJack
//
//  The lifter's own exercise named exactly like a built-in one becomes that built-in, keeping
//  everything it logged. iPhone only: the watch gets the result through iCloud and its snapshot.
//

import Foundation
import OSLog
import SwiftData

extension ExerciseCatalog {
    /// Bumped when built-in exercises are added, so each device moves its own copies of them once.
    /// 2: the Smith machine lifts. 3: belt squat, landmine, back extension and the other added lifts.
    /// An own exercise made later under a built-in name keeps its own identity, as it always has.
    static let sameNameRevision = 3
    static let sameNameRevisionKey = "catalog.sameNameRevision"

    /// Turns each own exercise named exactly like a built-in one (as `matchingName` reads both) into
    /// that built-in, in place, so its templates, programs, logged sets, imports, saved history, lift
    /// record and charts all stay with it. It takes the built-in name, equipment and muscles, and keeps
    /// its own rep range, fatigue level and rest. Where the built-in row exists too, `seed` then merges
    /// the two and keeps the older one on every device (`survivesBefore`).
    ///
    /// Each device moves the rows it holds, the same way, so two devices doing it at once agree.
    /// Older versions never turn a built-in row back into an own one.
    /// - Returns: The names moved, for the trace.
    @MainActor
    @discardableResult
    static func adoptSameNameCopies(in context: ModelContext, defaults: UserDefaults = .standard) throws -> [String] {
        guard SyncDevice.current == SyncDevice.iPhone,
              defaults.integer(forKey: sameNameRevisionKey) < sameNameRevision
        else { return [] }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        // The names each built-in row shows. A built-in the lifter renamed keeps their own lift under
        // its old name apart: it is a different lift to them.
        var builtInNames: [String: Set<String>] = [:]
        for exercise in exercises {
            guard let id = exercise.catalogID else { continue }
            builtInNames[id, default: []].insert(matchingName(exercise.exerciseName))
        }

        var moved: [(oldKeys: [String], newKey: String, name: String)] = []
        for exercise in exercises where exercise.catalogID == nil {
            let name = matchingName(exercise.exerciseName)
            guard let entry = entriesByMatchingName[name] else { continue }
            if let names = builtInNames[entry.id], !names.contains(name) { continue }

            let oldKeys = ExerciseRemoval.historyKeys(of: exercise)
            let strengthKey = StrengthLifts.key(for: exercise)
            entry.adopt(exercise)
            try ExerciseRemoval.moveHistory(from: oldKeys, strengthKey: strengthKey, to: exercise, in: context)
            moved.append((oldKeys, exercise.syncKey ?? exercise.exerciseName, entry.name))
        }

        if context.hasChanges { try context.save() }
        for item in moved {
            StudyOptions.replaceExercise(item.oldKeys, with: item.newKey, in: defaults)
        }
        defaults.set(sameNameRevision, forKey: sameNameRevisionKey)
        if !moved.isEmpty {
            TraceLog.record(.data, "Moved \(moved.count) own exercises to their built-in ones")
            Logger.sync.info("Moved \(moved.count) own exercises named like built-in ones")
        }
        return moved.map(\.name)
    }
}

extension ExerciseCatalog.Entry {
    /// Makes an own exercise this built-in one. Its rep range, fatigue level and rest are the lifter's.
    func adopt(_ exercise: Exercise) {
        exercise.catalogID = id
        exercise.userCreatedValue = false
        exercise.exerciseName = name
        exercise.equipment = equipment
        exercise.customEquipmentName = equipmentName
        exercise.primaryMuscleFocus = primaryMuscle
        exercise.secondaryMuscles = secondaryMuscles
        // Built-in exercises are never archived.
        exercise.archivedAtValue = nil
    }
}
