//
//  SetEntry.swift
//  PowerJack
//
//  The weight and reps of one set as the watch dials them in with the Digital Crown,
//  then logs with one tap.
//

import Foundation

struct SetEntry: Equatable {
    /// In `unit`. Bodyweight sets leave it at 0.
    var weight: Double
    var reps: Int
    let unit: WeightUnit
    /// One click of the Digital Crown, in `unit`.
    let weightStep: Double

    /// Starts on what the set holds: what's entered, else its target. A set with nothing yet
    /// starts at the empty bar for a barbell, and at the exercise's lowest rep target.
    init(for workoutSet: WorkoutSet, unit: WeightUnit = .current) {
        let workoutExercise = workoutSet.workoutExerciseValue
        let equipment = workoutExercise?.exercise?.exerciseEquipment ?? .machine
        self.unit = unit
        self.weightStep = StrengthLoadSteps.step(for: equipment, in: unit) ?? 1

        if let tenths = workoutSet.weightTenthsPounds ?? workoutSet.weightTenthsPlannedPounds {
            weight = unit.value(fromTenthsPounds: tenths)
        } else if equipment == .barbell {
            weight = unit == .kilograms ? LoadGrid.barKilograms : LoadGrid.barPounds
        } else {
            weight = 0
        }

        reps = workoutSet.reps
            ?? workoutSet.repsPlanned
            ?? workoutExercise?.targetReps
            ?? workoutExercise?.exercise?.minReps
            ?? Exercise.defaultMinReps
    }

    /// The weight counted in load steps, so each click of the Digital Crown is one step, whatever its size.
    var weightSteps: Double {
        get { weight / weightStep }
        set { weight = newValue.rounded() * weightStep }
    }

    /// The heaviest weight a set can log, in load steps.
    var maxWeightSteps: Double {
        (unit.maxEntry / weightStep).rounded(.down)
    }

    /// `nil` until a weight is dialed in, so an empty weight is never logged.
    var weightTenthsPounds: Int? {
        weight > 0 ? unit.tenthsPounds(from: weight) : nil
    }
}

extension WorkoutExercise {
    /// Logs `entry` on `workoutSet` and completes it. As when typing it on the phone, the weight carries
    /// to the later sets still to do, except from a TOP set, which is heavier than the BACK sets after it.
    func log(_ entry: SetEntry, on workoutSet: WorkoutSet, at date: Date = .now) {
        guard workoutSet.status == .active, !workoutSet.locked, WorkoutSet.isValidReps(entry.reps) else { return }
        let repsOnly = exercise?.repsOnly ?? false
        guard repsOnly || entry.weightTenthsPounds != nil else { return }

        workoutSet.reps = entry.reps
        if !repsOnly {
            workoutSet.weightTenthsPounds = entry.weightTenthsPounds
            if !isTopSet(workoutSet) {
                applyWeight(workoutSet.weightTenthsPounds, after: workoutSet)
            }
        }
        completeSet(workoutSet, at: date)
    }

    /// The set to log next on this exercise. Once every working set is done, leftover warmups aren't waiting.
    var nextSet: WorkoutSet? {
        guard !allSetsDone() else { return nil }
        return workoutSets.first { $0.status == .active }
    }
}
