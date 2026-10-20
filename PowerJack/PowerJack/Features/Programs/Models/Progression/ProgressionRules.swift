//
//  ProgressionRules.swift
//  PowerJack
//
//  Picks how a program progresses from the type of template it started from.
//

import Foundation

/// Writes a program's weeks for one template type.
protocol WeekPlanner {
    /// Runs once when a program is created, after week 1 is copied from its template.
    static func setUpFirstWeek(_ week: ProgramWeek, in program: Program)
    /// Fills an empty `week` once the week before it is finished.
    static func build(_ week: ProgramWeek, in program: Program)
    /// Runs right before `workout` starts.
    static func prepareToStart(_ workout: Workout, in program: Program, at date: Date)
}

extension WeekPlanner {
    static func setUpFirstWeek(_ week: ProgramWeek, in program: Program) {}
    static func prepareToStart(_ workout: Workout, in program: Program, at date: Date) {}
}

extension ProgressionPlanner: WeekPlanner {}

extension TemplateType {
    /// Writes the weeks of programs of this type.
    var weekPlanner: any WeekPlanner.Type {
        switch self {
        case .hypertrophy:
            BuildPlanner.self
        case .strength:
            ProgressionPlanner.self
        case .powerJack:
            PowerJackPlanner.self
        }
    }

    /// Decides an exercise's next planned version for programs that use `ProgressionPlanner`.
    /// Strengthen uses the original rules until it gets its own.
    var progressionRules: (ProgressionInput) -> Prescription {
        switch self {
        case .hypertrophy, .strength, .powerJack:
            ProgressionEngine.nextPrescription
        }
    }

    /// Effort is rated as reps left on the last set rather than with `LevelOfEffort` words.
    var ratesRepsInReserve: Bool {
        switch self {
        case .hypertrophy, .powerJack:
            true
        case .strength:
            false
        }
    }
}
