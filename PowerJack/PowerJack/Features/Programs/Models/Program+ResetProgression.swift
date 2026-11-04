//
//  Program+ResetProgression.swift
//  PowerJack
//
//  Reset Progression: plans this week's workouts that haven't started again, with the program's
//  current progression rules.
//

import Foundation
import OSLog

extension Program {
    /// The week the next workout is in.
    var currentWeek: ProgramWeek? {
        nextWorkout.flatMap(programWeek(containing:))
    }

    /// This week's workouts that haven't started. Started, finished and skipped ones are never changed.
    private var workoutsToReplan: [Workout] {
        currentWeek?.workouts.filter { $0.status == .planned } ?? []
    }

    var canResetProgression: Bool {
        guard let week = currentWeek, !workoutsToReplan.isEmpty else { return false }
        return templateType.weekPlanner.canReplan(week, in: self)
    }

    /// Writes new sets, reps and weights on this week's workouts that haven't started, replacing any edits.
    /// Each day keeps its exercises.
    func resetProgression() {
        guard canResetProgression, let week = currentWeek else {
            Logger.program.warning("This Program has no workouts to reset this week.")
            return
        }
        templateType.weekPlanner.replan(workoutsToReplan, of: week, in: self)
    }
}

extension Workout {
    /// Pairs each exercise with the same exercise of `source`, the same day of an earlier week: the first
    /// with the first, the second with the second. Exercises `source` doesn't have are left out.
    func slotPairs(with source: Workout) -> [(WorkoutExercise, WorkoutExercise)] {
        var unmatched = source.workoutExercises
        return workoutExercises.compactMap { workoutExercise in
            guard
                let exercise = workoutExercise.exercise,
                let index = unmatched.firstIndex(where: { $0.exercise === exercise })
            else { return nil }
            return (workoutExercise, unmatched.remove(at: index))
        }
    }
}
