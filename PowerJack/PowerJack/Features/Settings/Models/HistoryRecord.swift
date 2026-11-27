//
//  HistoryRecord.swift
//  PowerJack
//
//  The long view of the lifter's training: one saved row per set of every program that ended,
//  holding everything the history export shows. Rows are added when a program finishes, is
//  skipped for another or is deleted, and they stay after the program is gone, so the export
//  is quick and keeps everything. A row points back to its program only by the program's ID.
//

import Foundation
import SwiftData

/// How a program in the history ended, or that it's still going.
enum HistoryProgramStatus: String, CaseIterable {
    case planned = "Planned"
    case inProgress = "In Progress"
    case completed = "Completed"
    case skipped = "Skipped"
    case deleted = "Deleted"

    init(_ status: Status) {
        switch status {
        case .planned: self = .planned
        case .active: self = .inProgress
        case .complete: self = .completed
        case .skipped, .stopped: self = .skipped
        }
    }
}

/// One set as the history export shows it, before names the lifter typed are hidden and
/// weights take the lifter's unit.
struct HistoryRow: Equatable {
    var programID: UUID?
    var programName = ""
    var programType = ""
    var programWeeks = 0
    var daysPerWeek = 0
    var programStatus = HistoryProgramStatus.planned
    var week = 0
    var weekType = ""
    var day = 0
    var workoutStatus = ""
    var workoutStarted: Date?
    var workoutEnded: Date?
    var workoutSeconds: Double?
    var exerciseNumber = 0
    var exerciseName = ""
    /// Tells the lifter's own exercises apart when their names are hidden.
    var exerciseKey = ""
    var exerciseSource = ""
    var equipment = ""
    var primaryMuscle = ""
    var superset = ""
    var exerciseStatus = ""
    var effort = ""
    var pain = ""
    var topSetRIR = ""
    var rirTarget = ""
    var progression = ""
    var setType = ""
    var setNumber = 0
    var setStatus = ""
    var targetReps: Int?
    var reps: Int?
    var targetWeightTenthsPounds: Int?
    var weightTenthsPounds: Int?
    var setStarted: Date?
    var setLogged: Date?
    var setSeconds: Int?

    var isCustomExercise: Bool { exerciseSource == "Custom" }
}

@Model
final class HistoryRecord {
    // Speeds up fetches that filter or sort by these. Local store only: iCloud records carry no indexes.
    // Indexes alone don't change the model's hash, so the hash modifier below makes existing stores migrate and build them.
    #Index<HistoryRecord>([\.programIDValue])

    // Every field has a default or is optional and there are no relationships, so the rows
    // sync with iCloud and any later field can be added the same way.
    @Attribute(hashModifier: "indexes-1")
    var programIDValue: UUID?
    /// The rows saved together for one program. Two iPhones can each save a program before
    /// iCloud brings the other's rows, and the export keeps only one batch.
    var batchIDValue: UUID?
    var savedAtValue: Date?
    /// The program's first workout, which orders programs in the export.
    var programStartedValue: Date?
    /// The row's place in its program: week, day, exercise and set order.
    var orderValue: Int = 0
    /// A `HistoryProgramStatus` raw value.
    var programStatusValue: String = ""

    var programNameValue: String = ""
    var programTypeValue: String = ""
    var programWeeksValue: Int = 0
    var daysPerWeekValue: Int = 0
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
    var setTypeValue: String = ""
    var setNumberValue: Int = 0
    var setStatusValue: String = ""
    var targetRepsValue: Int?
    var repsValue: Int?
    var targetWeightTenthsPoundsValue: Int?
    var weightTenthsPoundsValue: Int?
    var setStartedValue: Date?
    var setLoggedValue: Date?
    var setSecondsValue: Int?

    init(_ row: HistoryRow, batchID: UUID, savedAt: Date, programStarted: Date?, order: Int) {
        batchIDValue = batchID
        savedAtValue = savedAt
        programStartedValue = programStarted
        orderValue = order
        programIDValue = row.programID
        programStatusValue = row.programStatus.rawValue
        programNameValue = row.programName
        programTypeValue = row.programType
        programWeeksValue = row.programWeeks
        daysPerWeekValue = row.daysPerWeek
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
        setTypeValue = row.setType
        setNumberValue = row.setNumber
        setStatusValue = row.setStatus
        targetRepsValue = row.targetReps
        repsValue = row.reps
        targetWeightTenthsPoundsValue = row.targetWeightTenthsPounds
        weightTenthsPoundsValue = row.weightTenthsPounds
        setStartedValue = row.setStarted
        setLoggedValue = row.setLogged
        setSecondsValue = row.setSeconds
    }
}

extension HistoryRecord {
    var programID: UUID? { programIDValue }
    var batchID: UUID? { batchIDValue }
    var savedAt: Date { savedAtValue ?? .distantPast }
    var programStarted: Date { programStartedValue ?? .distantFuture }
    var order: Int { orderValue }
    // A value saved by a later version that this one doesn't know reads as the program having ended.
    var programStatus: HistoryProgramStatus { HistoryProgramStatus(rawValue: programStatusValue) ?? .completed }

    func markDeleted() {
        programStatusValue = HistoryProgramStatus.deleted.rawValue
    }

    /// Shows a fix made to the set after its program ended.
    func correct(reps: Int?, weightTenthsPounds: Int?) {
        repsValue = reps
        weightTenthsPoundsValue = weightTenthsPounds
    }

    var row: HistoryRow {
        HistoryRow(
            programID: programIDValue,
            programName: programNameValue,
            programType: programTypeValue,
            programWeeks: programWeeksValue,
            daysPerWeek: daysPerWeekValue,
            programStatus: programStatus,
            week: weekValue,
            weekType: weekTypeValue,
            day: dayValue,
            workoutStatus: workoutStatusValue,
            workoutStarted: workoutStartedValue,
            workoutEnded: workoutEndedValue,
            workoutSeconds: workoutSecondsValue,
            exerciseNumber: exerciseNumberValue,
            exerciseName: exerciseNameValue,
            exerciseKey: exerciseKeyValue,
            exerciseSource: exerciseSourceValue,
            equipment: equipmentValue,
            primaryMuscle: primaryMuscleValue,
            superset: supersetValue,
            exerciseStatus: exerciseStatusValue,
            effort: effortValue,
            pain: painValue,
            topSetRIR: topSetRIRValue,
            rirTarget: rirTargetValue,
            progression: progressionValue,
            setType: setTypeValue,
            setNumber: setNumberValue,
            setStatus: setStatusValue,
            targetReps: targetRepsValue,
            reps: repsValue,
            targetWeightTenthsPounds: targetWeightTenthsPoundsValue,
            weightTenthsPounds: weightTenthsPoundsValue,
            setStarted: setStartedValue,
            setLogged: setLoggedValue,
            setSeconds: setSecondsValue
        )
    }
}
