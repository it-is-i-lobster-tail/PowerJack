//
//  ExerciseDraft.swift
//  PowerJack
//
//  Created on 7/8/26.
//

import Foundation

struct ExerciseDraft {
    var name: String = ""
    var equipment: Equipment?
    var customEquipmentName: String?
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
    /// The built-in lift (its sync key) whose pattern, style and joint actions this one copies.
    /// Proposed from the name until the lifter picks one, or None.
    private(set) var movesLike: String?
    private(set) var isMovesLikeChosen = false
    /// What the exercise had when the form opened, so saving rewrites its movement only if it changed.
    private var savedMovesLike: String?
    /// Secondary muscles filled in from `movesLike`. Once the lifter changes them, they stay.
    private var suggestedSecondary: [Muscle] = []

    static let repLimits = Exercise.minRepsAllowed...Exercise.maxRepsAllowed
    static let restLimits = Int(RestLength.range.lowerBound.components.seconds)
        ... Int(RestLength.range.upperBound.components.seconds)

    init() {}

    /// Starts a new exercise with a name, such as the search text that found nothing.
    init(name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(exercise: Exercise) {
        name = exercise.exerciseName
        equipment = exercise.equipment
        customEquipmentName = exercise.customEquipmentName
        primaryMuscle = exercise.primaryMuscleFocus
        secondaryMuscles = exercise.secondaryMusclesValue
        minReps = exercise.minReps
        maxReps = exercise.maxReps
        fatigueLevel = exercise.fatigueLevel
        customRestTime = exercise.customRestTime
        isBuiltIn = !exercise.userCreated
        movesLike = MovesLike.key(of: exercise)
        savedMovesLike = movesLike
        isMovesLikeChosen = movesLike != nil
    }

    /// The pattern, style and joint actions saving copies.
    var structure: MovementCatalog.Profile? { MovesLike.entry(movesLike)?.profile }

    var movesLikeName: String? { MovesLike.entry(movesLike)?.name }

    /// Whether the form should still propose a lift from the name.
    var wantsMovesLikeProposal: Bool { !isBuiltIn && !isMovesLikeChosen }

    /// A proposal from the name. Ignored once the lifter has chosen.
    mutating func propose(movesLike key: String?) {
        guard wantsMovesLikeProposal else { return }
        movesLike = key
        suggestSecondaryMuscles()
    }

    /// The lifter's own pick, or nil for None, which keeps the muscles as they are.
    mutating func choose(movesLike key: String?) {
        guard !isBuiltIn else { return }
        isMovesLikeChosen = true
        movesLike = key
        if key != nil { suggestSecondaryMuscles() }
    }

    /// Fills secondary muscles from `movesLike` while the lifter hasn't picked their own.
    /// The primary muscle is never set for them.
    private mutating func suggestSecondaryMuscles() {
        guard secondaryMuscles.isEmpty || secondaryMuscles == suggestedSecondary else { return }
        suggestedSecondary = MovesLike.secondaryMuscles(of: movesLike, primary: primaryMuscle)
        secondaryMuscles = suggestedSecondary
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
        suggestedSecondary.removeAll { $0 == primaryMuscle }
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
        exercise.customEquipmentName = customEquipmentName
        exercise.customRestTime = customRestTime
        return exercise
    }

    @discardableResult
    func apply(to exercise: Exercise) -> Bool {
        guard canSave else { return false }

        // Name, equipment and muscles only change on exercises the user created.
        if exercise.userCreated, !isBuiltIn, let equipment, let primaryMuscle {
            exercise.exerciseName = trimmedName
            exercise.equipment = equipment
            exercise.customEquipmentName = customEquipmentName
            exercise.primaryMuscleFocus = primaryMuscle
            exercise.secondaryMuscles = secondaryMuscles
        }
        exercise.minReps = minReps
        exercise.maxReps = maxReps
        exercise.fatigueLevel = fatigueLevel
        exercise.customRestTime = customRestTime
        applyMovement(to: exercise)
        return true
    }

    /// Writes `movesLike` onto an own exercise in a store, if it changed since the form opened.
    /// `makeExercise()` can't, because the exercise isn't in a store yet: insert it first.
    func applyMovement(to exercise: Exercise) {
        guard exercise.userCreated, !isBuiltIn, movesLike != savedMovesLike,
              let context = exercise.modelContext else { return }
        MovesLike.copy(movesLike, to: exercise, in: context)
    }
}
