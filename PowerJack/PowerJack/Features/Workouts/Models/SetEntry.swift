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

    /// Whether this entry holds what `workoutSet` shows: what's entered, else its target.
    func matches(_ workoutSet: WorkoutSet, repsOnly: Bool) -> Bool {
        reps == workoutSet.upcomingReps && (repsOnly || weightTenthsPounds == workoutSet.upcomingWeightTenthsPounds)
    }

    /// The part of this entry that differs from what `workoutSet` shows (what's entered, else its
    /// target), so only what the lifter changed is entered. Bodyweight sets compare reps only.
    func changes(from workoutSet: WorkoutSet, repsOnly: Bool) -> (weightTenthsPounds: Int?, reps: Int?) {
        let weight = repsOnly ? nil : weightTenthsPounds
        return (
            weight == workoutSet.upcomingWeightTenthsPounds ? nil : weight,
            reps == workoutSet.upcomingReps ? nil : reps
        )
    }
}

extension WorkoutExercise {
    /// Logs `entry` on `workoutSet` and completes it. As when typing it on the phone, the weight carries
    /// to the later sets still to do, except from a TOP set, which is heavier than the BACK sets after it.
    func log(_ entry: SetEntry, on workoutSet: WorkoutSet, at date: Date = .now) {
        log(weightTenthsPounds: entry.weightTenthsPounds, reps: entry.reps, on: workoutSet, at: date)
    }

    /// Logs `reps` at `weightTenthsPounds` on `workoutSet`, as `log(_:on:at:)` does. The iPhone runs
    /// this too for a set logged on the watch, naming the watch as the `device`.
    func log(weightTenthsPounds: Int?, reps: Int, on workoutSet: WorkoutSet, at date: Date = .now, device: String = SyncDevice.current) {
        guard workoutSet.status == .active, !workoutSet.locked, WorkoutSet.isValidReps(reps) else { return }
        let repsOnly = exercise?.repsOnly ?? false
        guard repsOnly || weightTenthsPounds != nil else { return }

        enter(weightTenthsPounds: weightTenthsPounds, reps: reps, on: workoutSet)
        completeSet(workoutSet, at: date, on: device)
    }

    /// Enters weight and reps on a set still to do without logging it, as typing them on the iPhone
    /// does: the weight carries to the later sets still holding the old one, except from a TOP set.
    /// Nil leaves that value as it is. The iPhone runs this too for what was dialed in on the watch.
    func enter(weightTenthsPounds: Int?, reps: Int?, on workoutSet: WorkoutSet) {
        guard workoutSet.status == .active, !workoutSet.locked else { return }
        if let reps, WorkoutSet.isValidReps(reps) {
            workoutSet.reps = reps
        }
        guard let weightTenthsPounds, !(exercise?.repsOnly ?? false) else { return }
        let previousWeight = workoutSet.weightTenthsPounds
        workoutSet.weightTenthsPounds = weightTenthsPounds
        if !isTopSet(workoutSet) {
            applyWeight(workoutSet.weightTenthsPounds, after: workoutSet, replacing: previousWeight)
        }
    }

    /// The set to log next on this exercise. Once every working set is done, leftover warmups aren't waiting.
    var nextSet: WorkoutSet? {
        guard !allSetsDone() else { return nil }
        return workoutSets.first { $0.status == .active }
    }
}
