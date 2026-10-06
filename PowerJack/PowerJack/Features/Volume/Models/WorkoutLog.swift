//
//  WorkoutLog.swift
//  PowerJack
//
//  One row per finished workout: working sets per muscle plus the date.
//  It has no relationship to the workout, so deleting a program keeps its history.
//

import Foundation
import SwiftData

@Model
final class WorkoutLog {
    private var dateValue: Date = Date.now
    private var chestValue: Double = 0
    private var shouldersValue: Double = 0
    private var backValue: Double = 0
    private var bicepsValue: Double = 0
    private var tricepsValue: Double = 0
    private var absValue: Double = 0
    private var obliquesValue: Double = 0
    private var forearmsValue: Double = 0
    private var quadsValue: Double = 0
    private var glutesValue: Double = 0
    private var calvesValue: Double = 0
    private var hamstringsValue: Double = 0

    init(date: Date, setsByMuscle: [Muscle: Double]) {
        self.dateValue = date
        for (muscle, sets) in setsByMuscle {
            setSets(sets, for: muscle)
        }
    }
}

//
// Public Accessors
//
extension WorkoutLog {
    // Date
    var date: Date { dateValue }

    /// Sets logged for `muscle`. A secondary muscle counts as half a set.
    func sets(for muscle: Muscle) -> Double {
        switch muscle {
        case .chest: chestValue
        case .shoulders: shouldersValue
        case .back: backValue
        case .biceps: bicepsValue
        case .triceps: tricepsValue
        case .abs: absValue
        case .obliques: obliquesValue
        case .forearms: forearmsValue
        case .quads: quadsValue
        case .glutes: glutesValue
        case .calves: calvesValue
        case .hamstrings: hamstringsValue
        }
    }

    private func setSets(_ sets: Double, for muscle: Muscle) {
        switch muscle {
        case .chest: chestValue = sets
        case .shoulders: shouldersValue = sets
        case .back: backValue = sets
        case .biceps: bicepsValue = sets
        case .triceps: tricepsValue = sets
        case .abs: absValue = sets
        case .obliques: obliquesValue = sets
        case .forearms: forearmsValue = sets
        case .quads: quadsValue = sets
        case .glutes: glutesValue = sets
        case .calves: calvesValue = sets
        case .hamstrings: hamstringsValue = sets
        }
    }
}

extension Workout {
    /// Completed working sets per muscle: 1 for the primary muscle, 0.5 for each secondary.
    /// Warmups and skipped sets are left out.
    var loggedSetsByMuscle: [Muscle: Double] {
        var setsByMuscle: [Muscle: Double] = [:]
        for workoutExercise in workoutExercises {
            guard let exercise = workoutExercise.exercise else { continue }
            let sets = Double(workoutExercise.completedWorkingSets)
            guard sets > 0 else { continue }

            setsByMuscle[exercise.primaryMuscleFocus, default: 0] += sets
            for muscle in exercise.secondaryMuscles where muscle != exercise.primaryMuscleFocus {
                setsByMuscle[muscle, default: 0] += sets / 2
            }
        }
        return setsByMuscle
    }
}
