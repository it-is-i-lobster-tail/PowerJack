//
//  ProgressionRules.swift
//  PowerJack
//
//  Picks how a program progresses from the type of template it started from.
//

import Foundation
import OSLog

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

/// What every planner's `build` shares: the week it builds, and the days it copies from the week before.
extension WeekPlanner {
    /// Where `week` sits in `program`, when `build` can fill it: it's empty and follows another week.
    static func buildIndex(of week: ProgramWeek, in program: Program) -> Int? {
        guard
            week.workouts.isEmpty,
            let index = program.programWeeks.firstIndex(where: { $0 === week }),
            index > 0
        else {
            Logger.program.warning("Can only build an empty ProgramWeek that follows another week.")
            return nil
        }
        return index
    }

    /// Gives the empty `week` the days and exercises of `source`, in order. A row whose exercise is gone is
    /// left out. Each new exercise keeps its day's warmup setting and superset, then `copied` runs with it,
    /// the exercise it copies, and that exercise's day, before the next exercise is added.
    static func copyDays(
        of source: ProgramWeek,
        into week: ProgramWeek,
        copied: (_ workoutExercise: WorkoutExercise, _ sourceExercise: WorkoutExercise, _ sourceWorkout: Workout) -> Void = { _, _, _ in }
    ) {
        for sourceWorkout in source.workouts {
            guard let workout = week.addWorkout() else { continue }
            for sourceExercise in sourceWorkout.workoutExercises {
                guard
                    let exercise = sourceExercise.exercise,
                    let workoutExercise = workout.addWorkoutExercise(exercise: exercise)
                else { continue }
                // An exercise with warmups disabled on this day gets none (see `WorkoutExercise.canAddSet`).
                workoutExercise.inheritWarmupsDisabled(from: sourceExercise)
                workoutExercise.inheritSuperset(from: sourceExercise)
                copied(workoutExercise, sourceExercise, sourceWorkout)
            }
        }
    }
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
