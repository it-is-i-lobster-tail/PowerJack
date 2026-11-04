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
    /// Runs when a week ends with no week after it to build: the program's last week, or the week a stopped
    /// program was partway through.
    static func close(_ week: ProgramWeek, in program: Program)
    /// Whether `replan` can write `week` again.
    static func canReplan(_ week: ProgramWeek, in program: Program) -> Bool
    /// Writes the sets of `workouts`, not started yet, of `week` again, as the planner would plan them now.
    /// The days keep their exercises.
    static func replan(_ workouts: [Workout], of week: ProgramWeek, in program: Program)
}

extension WeekPlanner {
    static func setUpFirstWeek(_ week: ProgramWeek, in program: Program) {}
    static func prepareToStart(_ workout: Workout, in program: Program, at date: Date) {}
    static func close(_ week: ProgramWeek, in program: Program) {}
    static func canReplan(_ week: ProgramWeek, in program: Program) -> Bool { true }
}

extension ProgressionPlanner: WeekPlanner {}

extension TemplateType {
    /// Writes the weeks of programs of this type.
    var weekPlanner: any WeekPlanner.Type {
        switch self {
        case .hypertrophy:
            ProgressionPlanner.self
        case .strength:
            StrengthPlanner.self
        case .powerJack:
            PowerJackPlanner.self
        }
    }

    /// Decides an exercise's next planned version for programs that use `ProgressionPlanner`.
    /// Build programs use these: each set progresses from its own logged reps.
    var progressionRules: (ProgressionInput) -> Prescription {
        switch self {
        case .hypertrophy, .strength, .powerJack:
            ProgressionEngine.nextPrescription
        }
    }

    /// Effort is rated as reps left on the last set rather than with `LevelOfEffort` words.
    var ratesRepsInReserve: Bool {
        switch self {
        case .hypertrophy, .strength, .powerJack:
            true
        }
    }
}
