//
//  ResetProgressionSupport.swift
//  PowerJackTests
//
//  Reads a planned workout as plain text, so tests can compare a reset plan with a freshly built one.
//

@testable import PowerJack

extension Workout {
    /// One line per exercise: its reps-left aim, why it was planned, then each set as reps x weight (W for warmups).
    var planSummary: [String] {
        workoutExercises.map { exercise in
            let sets = exercise.workoutSets.map { set in
                "\(set.isWarmup ? "W" : "")\(set.repsPlanned.map(String.init) ?? "-")x\(set.weightTenthsPlannedPounds.map(String.init) ?? "-")"
            }
            let aim = exercise.rirTarget.map(String.init) ?? "-"
            return "\(aim) \(exercise.progressionCode ?? "-") \(exercise.checkIn) | " + sets.joined(separator: " ")
        }
    }
}
