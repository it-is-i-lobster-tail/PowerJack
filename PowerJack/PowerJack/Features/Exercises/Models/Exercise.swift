//
//  Exercise.swift
//  PowerJack
//
//  Created by Brendon on 6/25/26.
//

import Foundation
import SwiftData

let maxExerciseNameLengthInput: Int = 30
let maxSecondaryMuscles: Int = 4

@Model
final class Exercise {
    var catalogID: String? = nil
    var exerciseName: String
    var exerciseEquipment: Equipment
    var primaryMuscleFocus: Muscle
    var secondaryMusclesValue: [Muscle]
    var userCreatedValue: Bool
    // Hypertrophy rep range used by the progression engine.
    var minRepsValue: Int = Exercise.defaultMinReps
    var maxRepsValue: Int = Exercise.defaultMaxReps
    // Sets the rest between sets. The default lets older stores migrate.
    var fatigueValue: Fatigue = Exercise.defaultFatigue

    static let defaultMinReps = 8
    static let defaultMaxReps = 12
    // No rep value above this can be saved anywhere in the app.
    static let maxRepsAllowed = 30
    static let defaultFatigue = Fatigue.medium

    init(
        exerciseName: String,
        exerciseEquipment: Equipment,
        primaryMuscleFocus: Muscle,
        secondaryMuscles: [Muscle] = [],
        userCreated: Bool = false,
        minReps: Int = Exercise.defaultMinReps,
        maxReps: Int = Exercise.defaultMaxReps,
        fatigue: Fatigue = Exercise.defaultFatigue
    ) {
        self.exerciseName = exerciseName
        self.exerciseEquipment = exerciseEquipment
        self.primaryMuscleFocus = primaryMuscleFocus
        self.secondaryMusclesValue = secondaryMuscles
        self.userCreatedValue = userCreated
        self.minRepsValue = minReps
        self.maxRepsValue = maxReps
        self.fatigueValue = fatigue
    }
}

//
// Public
//
extension Exercise {
    var secondaryMuscles: [Muscle] {
        get { secondaryMusclesValue.sorted { $0.rawValue < $1.rawValue } }
        set {
            secondaryMusclesValue = newValue
        }
    }
    var userCreated: Bool { userCreatedValue }
    // Rep Range
    var minReps: Int {
        get { minRepsValue }
        set { minRepsValue = newValue }
    }
    var maxReps: Int {
        get { maxRepsValue }
        set { maxRepsValue = newValue }
    }
    var repRange: ClosedRange<Int> { minReps...max(minReps, maxReps) }
    // Reps-only exercises never progress by load.
    var repsOnly: Bool { exerciseEquipment == .bodyweight }
    // Fatigue
    var fatigue: Fatigue {
        get { fatigueValue }
        set { fatigueValue = newValue }
    }
    var restDuration: Duration { fatigue.restDuration }
}
