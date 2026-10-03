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
    var fatigue: Fatigue = Exercise.defaultFatigue

    static let repLimits = 1...Exercise.maxRepsAllowed

    init() {}

    init(exercise: Exercise) {
        name = exercise.exerciseName
        equipment = exercise.exerciseEquipment
        primaryMuscle = exercise.primaryMuscleFocus
        secondaryMuscles = exercise.secondaryMusclesValue
        minReps = exercise.minReps
        maxReps = exercise.maxReps
        fatigue = exercise.fatigue
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        guard equipment != nil,
              let primaryMuscle
        else {
            return false
        }

        return (4...maxExerciseNameLengthInput).contains(trimmedName.count) &&
            secondaryMuscles.count <= maxSecondaryMuscles &&
            !secondaryMuscles.contains(primaryMuscle) &&
            repRangeIsValid
    }

    var repRangeIsValid: Bool {
        Self.repLimits.contains(minReps) &&
            Self.repLimits.contains(maxReps) &&
            minReps <= maxReps
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

        return Exercise(
            exerciseName: trimmedName,
            exerciseEquipment: equipment,
            primaryMuscleFocus: primaryMuscle,
            secondaryMuscles: secondaryMuscles,
            userCreated: userCreated,
            minReps: minReps,
            maxReps: maxReps,
            fatigue: fatigue
        )
    }

    @discardableResult
    func apply(to exercise: Exercise) -> Bool {
        guard exercise.userCreated, canSave,
              let equipment,
              let primaryMuscle
        else {
            return false
        }

        exercise.exerciseName = trimmedName
        exercise.exerciseEquipment = equipment
        exercise.primaryMuscleFocus = primaryMuscle
        exercise.secondaryMuscles = secondaryMuscles
        exercise.minReps = minReps
        exercise.maxReps = maxReps
        exercise.fatigue = fatigue
        return true
    }
}
