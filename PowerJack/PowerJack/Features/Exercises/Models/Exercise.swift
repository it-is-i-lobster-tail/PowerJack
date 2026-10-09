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
    var exerciseName: String = ""
    var exerciseEquipment: Equipment = Equipment.barbell
    var primaryMuscleFocus: Muscle = Muscle.chest
    var secondaryMusclesValue: [Muscle] = []
    var userCreatedValue: Bool = false
    // Rows that use this exercise. Kept so CloudKit has both sides of each link.
    var templateExercisesValue: [TemplateExercise]? = []
    var workoutExercisesValue: [WorkoutExercise]? = []
    // Rows stored before this field existed read as the oldest, so catalog dedupe keeps them.
    var createdAtValue: Date = Date.distantPast
    // Hypertrophy rep range used by the progression engine.
    var minRepsValue: Int = Exercise.defaultMinReps
    var maxRepsValue: Int = Exercise.defaultMaxReps
    // Picks the rest between sets. The default lets older stores migrate.
    @Attribute(originalName: "fatigueValue")
    var fatigueLevelValue: FatigueLevel = Exercise.defaultFatigueLevel
    // Seconds of rest that replace the fatigue level's rest. Nil uses the fatigue level.
    var customRestTimeValue: Int? = nil
    // No longer read: warmups are now turned off per program day (`WorkoutExercise.warmupsDisabled`).
    // Kept so the synced CloudKit schema only ever grows.
    var warmupDisabledValue: Bool = false

    static let defaultMinReps = 5
    // No exercise can set a minimum rep target below this.
    static let minRepsAllowed = 5
    // No rep value above this can be saved anywhere in the app.
    static let maxRepsAllowed = 30
    static let defaultFatigueLevel = FatigueLevel.moderate
    static let defaultMaxReps = defaultFatigueLevel.defaultMaxReps

    init(
        exerciseName: String,
        exerciseEquipment: Equipment,
        primaryMuscleFocus: Muscle,
        secondaryMuscles: [Muscle] = [],
        userCreated: Bool = false,
        minReps: Int = Exercise.defaultMinReps,
        maxReps: Int? = nil,
        fatigueLevel: FatigueLevel = Exercise.defaultFatigueLevel
    ) {
        self.exerciseName = exerciseName
        self.exerciseEquipment = exerciseEquipment
        self.primaryMuscleFocus = primaryMuscleFocus
        self.secondaryMusclesValue = secondaryMuscles
        self.userCreatedValue = userCreated
        self.minRepsValue = minReps
        self.maxRepsValue = maxReps ?? fatigueLevel.defaultMaxReps
        self.fatigueLevelValue = fatigueLevel
        self.createdAtValue = .now
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
    // Fatigue level
    var fatigueLevel: FatigueLevel {
        get { fatigueLevelValue }
        set { fatigueLevelValue = newValue }
    }
    var customRestTime: Int? {
        get { customRestTimeValue }
        set { customRestTimeValue = newValue }
    }
    var restDuration: Duration { customRestTime.map { .seconds($0) } ?? fatigueLevel.restLength.duration }
}
