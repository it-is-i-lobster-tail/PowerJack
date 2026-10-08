//
//  ExerciseDraft.swift
//  PowerJack
//
//  Created by Brendon on 7/8/26.
//

import Foundation

struct ExerciseDraft {
    var name: String = ""
    var equipment: Equipment?
    var primaryMuscle: Muscle?
    var secondaryMuscles: [Muscle] = []
    var minReps: Int = Exercise.defaultMinReps
    var maxReps: Int = Exercise.defaultMaxReps
    var fatigueLevel: FatigueLevel = Exercise.defaultFatigueLevel {
        didSet {
            // Max reps follows the fatigue default until the user picks their own.
            guard maxReps == oldValue.defaultMaxReps else { return }
            maxReps = max(fatigueLevel.defaultMaxReps, minReps)
        }
    }
    // Seconds of rest that replace the fatigue level's rest. Nil uses the fatigue level.
    var customRestTime: Int?
    // Built-in exercises keep their name, equipment and muscles. Only rep range, fatigue and rest change.
    private(set) var isBuiltIn = false

    static let repLimits = Exercise.minRepsAllowed...Exercise.maxRepsAllowed
    static let restLimits = Int(RestLength.range.lowerBound.components.seconds)
        ... Int(RestLength.range.upperBound.components.seconds)
    static let restStep = 15

    init() {}

    init(exercise: Exercise) {
        name = exercise.exerciseName
        equipment = exercise.exerciseEquipment
        primaryMuscle = exercise.primaryMuscleFocus
        secondaryMuscles = exercise.secondaryMusclesValue
        minReps = exercise.minReps
        maxReps = exercise.maxReps
        fatigueLevel = exercise.fatigueLevel
        customRestTime = exercise.customRestTime
        isBuiltIn = !exercise.userCreated
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        guard !isBuiltIn else { return repRangeIsValid && restIsValid }
        guard equipment != nil,
              let primaryMuscle
        else {
            return false
        }

        return (4...maxExerciseNameLengthInput).contains(trimmedName.count) &&
            secondaryMuscles.count <= maxSecondaryMuscles &&
            !secondaryMuscles.contains(primaryMuscle) &&
            repRangeIsValid &&
            restIsValid
    }

    var repRangeIsValid: Bool {
        Self.repLimits.contains(minReps) &&
            Self.repLimits.contains(maxReps) &&
            minReps <= maxReps
    }

    var restIsValid: Bool {
        customRestTime.map(Self.restLimits.contains) ?? true
    }

    /// The rest the fatigue level gives, used as the starting point for a custom rest.
    var fatigueRestTime: Int {
        Int(fatigueLevel.restLength.duration.components.seconds)
    }

    mutating func removePrimaryFromSecondary() {
        guard let primaryMuscle else { return }
        secondaryMuscles.removeAll { $0 == primaryMuscle }
    }

    func makeExercise(userCreated: Bool = true) -> Exercise? {
        guard canSave,
              let equipment,
              let primaryMuscle
        else {
            return nil
        }

        let exercise = Exercise(
            exerciseName: trimmedName,
            exerciseEquipment: equipment,
            primaryMuscleFocus: primaryMuscle,
            secondaryMuscles: secondaryMuscles,
            userCreated: userCreated,
            minReps: minReps,
            maxReps: maxReps,
            fatigueLevel: fatigueLevel
        )
        exercise.customRestTime = customRestTime
        return exercise
    }

    @discardableResult
    func apply(to exercise: Exercise) -> Bool {
        guard canSave else { return false }

        // Name, equipment and muscles only change on exercises the user created.
        if exercise.userCreated, !isBuiltIn, let equipment, let primaryMuscle {
            exercise.exerciseName = trimmedName
            exercise.exerciseEquipment = equipment
            exercise.primaryMuscleFocus = primaryMuscle
            exercise.secondaryMuscles = secondaryMuscles
        }
        exercise.minReps = minReps
        exercise.maxReps = maxReps
        exercise.fatigueLevel = fatigueLevel
        exercise.customRestTime = customRestTime
        return true
    }
}
