//
//  HistoryShape.swift
//  PowerJack
//
//  The long history in a leaner shape: one `HistoryProgram` row per saved program and one
//  `HistoryExercise` row per exercise slot, with the slot's sets packed into it. It holds
//  everything `HistoryRecord` holds, so the export and the Data tab read the same from either.
//  Both shapes are written for now; `HistoryRecord` goes once every device reads this one
//  (see `DeviceSchemaMark`).
//

import Foundation
import SwiftData

@Model
final class HistoryProgram {
    // Every field has a default or is optional and there are no relationships, so the rows
    // sync with iCloud, like `HistoryRecord`.
    var programIDValue: UUID?
    /// The `HistoryRecord` batch these rows match. Two iPhones can each save a program, and the
    /// first batch saved wins.
    var batchIDValue: UUID?
    /// This copy of the batch. Two iPhones can each write the same batch from its old rows;
    /// its exercises carry the same ID, so reads keep one whole copy.
    var copyIDValue: UUID?
    var savedAtValue: Date?
    /// The program's first workout, which orders programs in the export.
    var programStartedValue: Date?
    /// A `HistoryProgramStatus` raw value.
    var programStatusValue: String = ""
    var programNameValue: String = ""
    var programTypeValue: String = ""
    var programWeeksValue: Int = 0
    var daysPerWeekValue: Int = 0

    init(_ row: HistoryRow, batchID: UUID, copyID: UUID, savedAt: Date, programStarted: Date?) {
        programIDValue = row.programID
        batchIDValue = batchID
        copyIDValue = copyID
        savedAtValue = savedAt
        programStartedValue = programStarted
        programStatusValue = row.programStatus.rawValue
        programNameValue = row.programName
        programTypeValue = row.programType
        programWeeksValue = row.programWeeks
        daysPerWeekValue = row.daysPerWeek
    }
}

@Model
final class HistoryExercise {
    var programIDValue: UUID?
    var batchIDValue: UUID?
    /// The `HistoryProgram` copy this slot belongs to.
    var copyIDValue: UUID?
    /// The slot's place in its program: week, day and exercise order.
    var orderValue: Int = 0
    var weekValue: Int = 0
    var weekTypeValue: String = ""
    var dayValue: Int = 0
    var workoutStatusValue: String = ""
    var workoutStartedValue: Date?
    var workoutEndedValue: Date?
    var workoutSecondsValue: Double?
    var exerciseNumberValue: Int = 0
    var exerciseNameValue: String = ""
    var exerciseKeyValue: String = ""
    var exerciseSourceValue: String = ""
    var equipmentValue: String = ""
    var primaryMuscleValue: String = ""
    var supersetValue: String = ""
    var exerciseStatusValue: String = ""
    var effortValue: String = ""
    var painValue: String = ""
    var topSetRIRValue: String = ""
    var rirTargetValue: String = ""
    var progressionValue: String = ""
    /// The slot's sets in order, as JSON `[HistorySet]`.
    var setsValue: Data?

    init(_ row: HistoryRow, sets: [HistorySet], batchID: UUID, copyID: UUID, order: Int) {
        programIDValue = row.programID
        batchIDValue = batchID
        copyIDValue = copyID
        orderValue = order
        weekValue = row.week
        weekTypeValue = row.weekType
        dayValue = row.day
        workoutStatusValue = row.workoutStatus
        workoutStartedValue = row.workoutStarted
        workoutEndedValue = row.workoutEnded
        workoutSecondsValue = row.workoutSeconds
        exerciseNumberValue = row.exerciseNumber
        exerciseNameValue = row.exerciseName
        exerciseKeyValue = row.exerciseKey
        exerciseSourceValue = row.exerciseSource
        equipmentValue = row.equipment
        primaryMuscleValue = row.primaryMuscle
        supersetValue = row.superset
        exerciseStatusValue = row.exerciseStatus
        effortValue = row.effort
        painValue = row.pain
        topSetRIRValue = row.topSetRIR
        rirTargetValue = row.rirTarget
        progressionValue = row.progression
        setsValue = try? JSONEncoder().encode(sets)
    }
}

/// One set of a `HistoryExercise`.
struct HistorySet: Codable, Equatable {
    var type = ""
    var number = 0
    var status = ""
    var targetReps: Int?
    var reps: Int?
    var targetWeightTenthsPounds: Int?
    var weightTenthsPounds: Int?
    var started: Date?
    var logged: Date?
    var seconds: Int?

    init(_ row: HistoryRow) {
        type = row.setType
        number = row.setNumber
        status = row.setStatus
        targetReps = row.targetReps
        reps = row.reps
        targetWeightTenthsPounds = row.targetWeightTenthsPounds
        weightTenthsPounds = row.weightTenthsPounds
        started = row.setStarted
        logged = row.setLogged
        seconds = row.setSeconds
    }
}

/// A saved set as the export and the Data tab read it, from either shape.
struct ArchivedRow: Equatable {
    var row: HistoryRow
    var batchID: UUID?
    var savedAt: Date
    var programStarted: Date
    /// The row's place in its program: week, day, exercise and set order.
    var order: Int

    var programID: UUID? { row.programID }
    var programStatus: HistoryProgramStatus { row.programStatus }
}

extension HistoryRecord {
    var archived: ArchivedRow {
        ArchivedRow(row: row, batchID: batchID, savedAt: savedAt, programStarted: programStarted, order: order)
    }
}

extension HistoryProgram {
    var programID: UUID? { programIDValue }
    var batchID: UUID? { batchIDValue }
    var copyID: UUID? { copyIDValue }

    func markDeleted() {
        programStatusValue = HistoryProgramStatus.deleted.rawValue
    }

    /// Rows for one saved program, in order, split into a program and its exercise slots.
    /// A slot is a run of rows with the same week, day and exercise number.
    static func make(
        from rows: [HistoryRow], batchID: UUID, savedAt: Date, programStarted: Date?
    ) -> (program: HistoryProgram, exercises: [HistoryExercise])? {
        guard let first = rows.first else { return nil }
        let copyID = UUID()
        var exercises: [HistoryExercise] = []
        var start = 0
        while start < rows.count {
            let slot = rows[start]
            var end = start + 1
            while end < rows.count, rows[end].week == slot.week, rows[end].day == slot.day,
                  rows[end].exerciseNumber == slot.exerciseNumber {
                end += 1
            }
            exercises.append(HistoryExercise(
                slot, sets: rows[start..<end].map(HistorySet.init), batchID: batchID, copyID: copyID, order: exercises.count
            ))
            start = end
        }
        let program = HistoryProgram(first, batchID: batchID, copyID: copyID, savedAt: savedAt, programStarted: programStarted)
        return (program, exercises)
    }

    /// The program's rows, from its exercises (any order, only this copy's are used).
    func archivedRows(_ exercises: [HistoryExercise]) -> [ArchivedRow] {
        let status = HistoryProgramStatus(rawValue: programStatusValue) ?? .completed
        let rows = exercises.filter { $0.copyIDValue == copyIDValue }.sorted { $0.orderValue < $1.orderValue }.flatMap { slot in
            slot.sets.map { set in
                HistoryRow(
                    programID: programIDValue,
                    programName: programNameValue,
                    programType: programTypeValue,
                    programWeeks: programWeeksValue,
                    daysPerWeek: daysPerWeekValue,
                    programStatus: status,
                    week: slot.weekValue,
                    weekType: slot.weekTypeValue,
                    day: slot.dayValue,
                    workoutStatus: slot.workoutStatusValue,
                    workoutStarted: slot.workoutStartedValue,
                    workoutEnded: slot.workoutEndedValue,
                    workoutSeconds: slot.workoutSecondsValue,
                    exerciseNumber: slot.exerciseNumberValue,
                    exerciseName: slot.exerciseNameValue,
                    exerciseKey: slot.exerciseKeyValue,
                    exerciseSource: slot.exerciseSourceValue,
                    equipment: slot.equipmentValue,
                    primaryMuscle: slot.primaryMuscleValue,
                    superset: slot.supersetValue,
                    exerciseStatus: slot.exerciseStatusValue,
                    effort: slot.effortValue,
                    pain: slot.painValue,
                    topSetRIR: slot.topSetRIRValue,
                    rirTarget: slot.rirTargetValue,
                    progression: slot.progressionValue,
                    setType: set.type,
                    setNumber: set.number,
                    setStatus: set.status,
                    targetReps: set.targetReps,
                    reps: set.reps,
                    targetWeightTenthsPounds: set.targetWeightTenthsPounds,
                    weightTenthsPounds: set.weightTenthsPounds,
                    setStarted: set.started,
                    setLogged: set.logged,
                    setSeconds: set.seconds
                )
            }
        }
        return rows.enumerated().map { order, row in
            ArchivedRow(row: row, batchID: batchIDValue, savedAt: savedAtValue ?? .distantPast,
                        programStarted: programStartedValue ?? .distantFuture, order: order)
        }
    }
}

extension HistoryExercise {
    var copyID: UUID? { copyIDValue }

    var sets: [HistorySet] {
        guard let setsValue else { return [] }
        return (try? JSONDecoder().decode([HistorySet].self, from: setsValue)) ?? []
    }

    /// Shows a fix made to a set after its program ended.
    func correct(setNumber: Int, setType: String, reps: Int?, weightTenthsPounds: Int?) {
        var sets = sets
        var changed = false
        for index in sets.indices where sets[index].number == setNumber && sets[index].type == setType {
            sets[index].reps = reps
            sets[index].weightTenthsPounds = weightTenthsPounds
            changed = true
        }
        if changed { setsValue = try? JSONEncoder().encode(sets) }
    }
}
