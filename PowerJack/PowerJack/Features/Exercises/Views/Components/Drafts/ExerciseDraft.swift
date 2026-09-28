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

    init() {}

    init(exercise: Exercise) {
        name = exercise.exerciseName
        equipment = exercise.exerciseEquipment
        primaryMuscle = exercise.primaryMuscleFocus
        secondaryMuscles = exercise.secondaryMusclesValue
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
            !secondaryMuscles.contains(primaryMuscle)
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
            userCreated: userCreated
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
        return true
    }
}
