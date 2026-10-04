//
//  Workout+Activity.swift
//  PowerJack
//
//  What the Live Activity shows for the active workout, and logging a set at its target.
//

import Foundation

extension Workout {
    /// The current set and the rest before it while that rest is still running.
    /// A rest that has already run out is left off: iOS drops an activity that starts out stale.
    func activityState(at now: Date = .now) -> WorkoutActivityState? {
        guard
            let current = currentSet,
            let exercise = current.workoutExercise.exercise
        else {
            return nil
        }

        let workoutSet = current.workoutSet
        let repsOnly = exercise.repsOnly
        return WorkoutActivityState(
            exerciseName: exercise.exerciseName,
            exerciseOrder: current.workoutExercise.order,
            setOrder: workoutSet.order,
            sets: current.workoutExercise.workoutSets.map { $0.activitySet(isCurrent: $0 === workoutSet, repsOnly: repsOnly) },
            repsOnly: repsOnly,
            canCompleteAtTarget: workoutSet.canCompleteAtTarget(repsOnly: repsOnly),
            rest: currentRest.flatMap { $0.isResting(at: now) ? $0.interval : nil }
        )
    }

    /// Logs the current set at its target, if it is the set at these positions and has a full target.
    @discardableResult
    func completeCurrentSetAtTarget(exerciseOrder: Int, setOrder: Int, at date: Date = .now) -> Bool {
        guard
            let current = currentSet,
            current.workoutExercise.order == exerciseOrder,
            current.workoutSet.order == setOrder,
            let exercise = current.workoutExercise.exercise
        else {
            return false
        }
        return current.workoutSet.completeAtTarget(repsOnly: exercise.repsOnly, at: date)
    }
}

extension WorkoutSet {
    /// What was logged once the set is done, its target until then.
    func activitySet(isCurrent: Bool, repsOnly: Bool) -> ActivitySet {
        let progress: ActivitySet.Progress = switch status {
        case .complete: .done
        case .skipped, .stopped: .skipped
        default: isCurrent ? .current : .upcoming
        }
        let isLogged = progress == .done
        return ActivitySet(
            progress: progress,
            reps: isLogged ? reps : repsPlanned,
            weightTenthsPounds: repsOnly ? nil : (isLogged ? weightTenthsPounds : weightTenthsPlannedPounds)
        )
    }

    /// Has a target to log (reps, plus weight unless reps only) and nothing different typed in yet.
    func canCompleteAtTarget(repsOnly: Bool) -> Bool {
        guard status == .active, !locked, let repsPlanned else { return false }
        guard reps == nil || reps == repsPlanned else { return false }
        if repsOnly { return true }
        guard let weightTenthsPlannedPounds else { return false }
        return weightTenthsPounds == nil || weightTenthsPounds == weightTenthsPlannedPounds
    }

    /// Logs the target weight and reps and completes the set.
    @discardableResult
    func completeAtTarget(repsOnly: Bool, at date: Date = .now) -> Bool {
        guard canCompleteAtTarget(repsOnly: repsOnly) else { return false }
        reps = repsPlanned
        if !repsOnly {
            weightTenthsPounds = weightTenthsPlannedPounds
        }
        complete(at: date)
        return true
    }
}

extension Program {
    /// e.g. "Day 2 · Week 1".
    func activityTitle(for workout: Workout) -> String {
        let day = "Day \(workout.order + 1)"
        guard let week = weekNumber(containing: workout) else { return day }
        return "\(day) · Week \(week)"
    }
}
