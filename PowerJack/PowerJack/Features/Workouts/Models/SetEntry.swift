//
//  SetEntry.swift
//  PowerJack
//
//  The weight and reps of one set as the watch dials them in with the Digital Crown,
//  then logs with one tap.
//

import Foundation

struct SetEntry: Equatable {
    /// In `unit`. An explicit zero means bodyweight alone on loadable bodyweight exercises.
    var weight: Double?
    var reps: Int?
    let unit: WeightUnit
    /// One click of the Digital Crown, in `unit`.
    let weightStep: Double
    /// Loadable bodyweight, where a weight of 0 is bodyweight alone and can be logged.
    let addsToBodyweight: Bool
    /// The weights the lifter owns, in `unit`, lightest first. Each click of the Digital Crown is the next one.
    let ownedWeights: [Double]?

    /// An entered value takes precedence over the prescription for this set.
    init(for workoutSet: WorkoutSet, unit: WeightUnit = .current) {
        let workoutExercise = workoutSet.workoutExerciseValue
        let equipment = workoutExercise?.shownExercise?.equipment ?? .machine
        self.unit = unit
        self.weightStep = StrengthLoadSteps.step(for: equipment, in: unit) ?? 1
        self.addsToBodyweight = equipment == .loadableBodyweight
        self.ownedWeights = OwnedLoads.active(for: equipment, in: unit)

        weight = workoutSet.upcomingWeightTenthsPounds.map { unit.value(fromTenthsPounds: $0) }
        reps = workoutSet.upcomingReps
    }

    /// The weight counted in load steps, so each click of the Digital Crown is one step, whatever its size.
    /// With owned weights, step n is the nth lightest one, and a weight typed between two sits between their steps.
    var weightSteps: Double {
        get {
            guard let weight else { return addsToBodyweight ? -1 : 0 }
            guard let ownedWeights else { return weight / weightStep }
            return Self.position(of: weight, in: ownedWeights)
        }
        set {
            var steps = newValue.rounded()
            // From a weight typed between two owned ones, the first click goes to the neighbour on that side.
            if let ownedWeights, let weight, weight > 0 {
                let current = Self.position(of: weight, in: ownedWeights)
                if current != current.rounded() {
                    let clicks = (newValue - current).rounded()
                    steps = newValue > current
                        ? current.rounded(.up) + max(clicks - 1, 0)
                        : current.rounded(.down) + min(clicks + 1, 0)
                }
            }
            guard steps > 0 else {
                if addsToBodyweight && steps == 0 { weight = 0 }
                return
            }
            if let ownedWeights {
                weight = ownedWeights[min(Int(steps), ownedWeights.count) - 1]
            } else {
                weight = steps * weightStep
            }
        }
    }

    /// The heaviest weight a set can log, in load steps.
    var maxWeightSteps: Double {
        if let ownedWeights { return Double(ownedWeights.count) }
        return (unit.maxEntry / weightStep).rounded(.down)
    }

    /// Where `weight` sits among `weights`: 1 for the lightest, 1.5 halfway to the next, and so on.
    private static func position(of weight: Double, in weights: [Double]) -> Double {
        guard weight > 0, let first = weights.first, let last = weights.last else { return 0 }
        if weight <= first { return weight / first }
        if weight >= last { return Double(weights.count) }
        let upper = weights.firstIndex { $0 >= weight } ?? weights.count - 1
        let lower = weights[upper - 1]
        return Double(upper) + (weight - lower) / (weights[upper] - lower)
    }

    /// `nil` until a weight is dialed in, so an empty weight is never logged. Loadable bodyweight logs 0 as bodyweight.
    var weightTenthsPounds: Int? {
        guard let weight else { return nil }
        return weight > 0 || addsToBodyweight ? unit.tenthsPounds(from: weight) : nil
    }

    /// Loadable bodyweight with nothing added.
    var isBodyweight: Bool { addsToBodyweight && weight == 0 }

    /// e.g. "225", or "BW" for bodyweight alone.
    var weightText: String {
        guard let weight else { return "—" }
        return isBodyweight ? "BW" : weight.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// Whether this entry holds what the dial starts on for `workoutSet`.
    func matches(_ workoutSet: WorkoutSet, repsOnly: Bool) -> Bool {
        let shown = SetEntry(for: workoutSet, unit: unit)
        return reps == shown.reps && (repsOnly || weightTenthsPounds == shown.weightTenthsPounds)
    }

    /// The part of this entry that differs from what the dial starts on for `workoutSet`, so only
    /// what the lifter changed is entered.
    /// Bodyweight sets compare reps only.
    func changes(from workoutSet: WorkoutSet, repsOnly: Bool) -> (weightTenthsPounds: Int?, reps: Int?) {
        let shown = SetEntry(for: workoutSet, unit: unit)
        let weight = repsOnly ? nil : weightTenthsPounds
        return (
            weight == shown.weightTenthsPounds ? nil : weight,
            reps == shown.reps ? nil : reps
        )
    }
}

extension WorkoutExercise {
    /// Logs `entry` on `workoutSet` and completes it. As when typing it on the phone, the weight carries
    /// to the later sets still to do, except from a TOP set, which is heavier than the BACK sets after it.
    func log(_ entry: SetEntry, on workoutSet: WorkoutSet, at date: Date = .now) {
        guard let reps = entry.reps else { return }
        log(weightTenthsPounds: entry.weightTenthsPounds, reps: reps, on: workoutSet, at: date)
    }

    /// Logs `reps` at `weightTenthsPounds` on `workoutSet`, as `log(_:on:at:)` does. The iPhone runs
    /// this too for a set logged on the watch, naming the watch as the `device`.
    func log(weightTenthsPounds: Int?, reps: Int, on workoutSet: WorkoutSet, at date: Date = .now, device: String = SyncDevice.current) {
        guard workoutSet.status == .active, !workoutSet.locked, WorkoutSet.isValidReps(reps) else { return }
        let repsOnly = shownExercise?.repsOnly ?? false
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
        guard let weightTenthsPounds, !(shownExercise?.repsOnly ?? false) else { return }
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
