//
//  SetReceipt.swift
//  PowerJack
//
//  A note written every time a set is logged, on whichever device logged it, and never changed.
//  When an older upload overwrites a set through iCloud, the tidy-up rebuilds it from the latest
//  receipt, and the earlier run is never truly lost. Like `WorkoutLog` it has no relationships,
//  so it outlives the program.
//

import Foundation
import SwiftData

@Model
final class SetReceipt {
    private var setIDValue: UUID?
    // The workout's sync ID.
    private var sessionIDValue: UUID?
    // The exercise's catalog ID, or its name for the lifter's own exercises.
    private var exerciseValue: String = ""
    private var weightTenthsPoundsValue: Int?
    private var repsValue: Int?
    private var completedAtValue: Date = Date.distantPast
    private var deviceValue: String = ""

    init(for workoutSet: WorkoutSet, device: String) {
        let workoutExercise = workoutSet.workoutExerciseValue
        self.setIDValue = workoutSet.syncID
        self.sessionIDValue = workoutExercise?.workoutValue?.syncID
        self.exerciseValue = workoutExercise?.exercise.map { $0.catalogID ?? $0.exerciseName } ?? ""
        self.weightTenthsPoundsValue = workoutSet.weightTenthsPounds
        self.repsValue = workoutSet.reps
        self.completedAtValue = workoutSet.completedAt ?? .now
        self.deviceValue = device
    }
}

extension SetReceipt {
    var setID: UUID? { setIDValue }
    var sessionID: UUID? { sessionIDValue }
    var exercise: String { exerciseValue }
    var device: String { deviceValue }
    var log: SetLog {
        SetLog(weightTenthsPounds: weightTenthsPoundsValue, reps: repsValue, completedAt: completedAtValue)
    }

    /// Receipts for sets logged at or after `date`.
    static func written(since date: Date, in context: ModelContext) throws -> [SetReceipt] {
        try context.fetch(FetchDescriptor<SetReceipt>(predicate: #Predicate { $0.completedAtValue >= date }))
    }

    /// Whether `workoutSet` was logged before `date`, so a log at `date` fixes it.
    static func wasLogged(_ workoutSet: WorkoutSet, before date: Date, in context: ModelContext?) -> Bool {
        guard let context, let setID = workoutSet.syncID else { return false }
        let earlier = date.addingTimeInterval(-SetLog.sameMoment)
        let descriptor = FetchDescriptor<SetReceipt>(predicate: #Predicate { $0.setIDValue == setID && $0.completedAtValue < earlier })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
