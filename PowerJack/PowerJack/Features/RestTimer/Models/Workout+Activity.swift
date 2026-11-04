//
//  Workout+Activity.swift
//  PowerJack
//
//  What the Live Activity shows for the active workout, and logging a set from it.
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

        let workoutExercise = current.workoutExercise
        let workoutSet = current.workoutSet
        let repsOnly = exercise.repsOnly
        return WorkoutActivityState(
            exerciseName: exercise.exerciseName,
            setText: workoutExercise.setText(for: workoutSet),
            exerciseOrder: workoutExercise.order,
            setOrder: workoutSet.order,
            sets: workoutExercise.workoutSets.map {
                $0.activitySet(
                    label: $0.isWarmup ? "W\(workoutExercise.number(of: $0))" : "\(workoutExercise.number(of: $0))",
                    isCurrent: $0 === workoutSet,
                    repsOnly: repsOnly
                )
            },
            repsOnly: repsOnly,
            canCompleteAtTarget: workoutSet.canCompleteAsEntered(repsOnly: repsOnly),
            rest: currentRest.flatMap { $0.isResting(at: now) ? $0.interval : nil }
        )
    }

    /// Logs the current set as entered, if it is the set at these positions and has weight and reps to log.
    @discardableResult
    func completeCurrentSet(exerciseOrder: Int, setOrder: Int, at date: Date = .now) -> Bool {
        guard
            let current = currentSet,
            current.workoutExercise.order == exerciseOrder,
            current.workoutSet.order == setOrder,
            let exercise = current.workoutExercise.exercise
        else {
            return false
        }
        return current.workoutSet.completeAsEntered(repsOnly: exercise.repsOnly, at: date)
    }
}

extension WorkoutSet {
    /// What the lifter typed in, else the set's target. The voice and Live Activity always say this.
    var upcomingReps: Int? { reps ?? repsPlanned }
    var upcomingWeightTenthsPounds: Int? { weightTenthsPounds ?? weightTenthsPlannedPounds }

    /// What was logged once the set is done, what's entered until then.
    func activitySet(label: String, isCurrent: Bool, repsOnly: Bool) -> ActivitySet {
        let progress: ActivitySet.Progress = switch status {
        case .complete: .done
        case .skipped, .stopped: .skipped
        default: isCurrent ? .current : .upcoming
        }
        return ActivitySet(
            label: label,
            progress: progress,
            reps: upcomingReps,
            weightTenthsPounds: repsOnly ? nil : upcomingWeightTenthsPounds,
            usesKilograms: WeightUnit.current == .kilograms
        )
    }

    /// Has reps to log, plus weight unless reps only.
    func canCompleteAsEntered(repsOnly: Bool) -> Bool {
        guard status == .active, !locked, upcomingReps != nil else { return false }
        return repsOnly || upcomingWeightTenthsPounds != nil
    }

    /// Logs the weight and reps entered, else the target, and completes the set.
    @discardableResult
    func completeAsEntered(repsOnly: Bool, at date: Date = .now) -> Bool {
        guard canCompleteAsEntered(repsOnly: repsOnly) else { return false }
        reps = upcomingReps
        if !repsOnly {
            weightTenthsPounds = upcomingWeightTenthsPounds
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
