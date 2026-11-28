//
//  ExerciseDraft.swift
//  PowerJack
//
//  Created on 7/8/26.
//

import Foundation
import SwiftData

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
    /// The built-in lifts (their sync keys), up to three, whose joint actions this one copies,
    /// the first also its pattern and style. Proposed from the name until the lifter picks, or None.
    private(set) var movesLike: [String] = []
    private(set) var isMovesLikeChosen = false
    /// What the exercise had when the form opened, so saving rewrites its movement only if it changed.
    private var savedMovesLike: [String] = []
    /// Secondary muscles filled in from `movesLike`. Once the lifter changes them, they stay.
    private var suggestedSecondary: [Muscle] = []
    /// Joint actions the lifter set in Advanced Data, replacing the `movesLike` lift's. Nil follows `movesLike`.
    private(set) var customActions: [JointAction]?
    private var savedCustomActions: [JointAction]?
    /// A built-in's joint actions, from the catalog.
    private var builtInActions: [JointAction] = []

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
        movesLike = MovesLike.keys(of: exercise)
        savedMovesLike = movesLike
        customActions = isBuiltIn ? nil : CustomJointActions.read(exercise) ?? Self.storedActions(of: exercise, movesLike: movesLike)
        savedCustomActions = customActions
        isMovesLikeChosen = !movesLike.isEmpty || customActions != nil
        builtInActions = ExerciseCatalog.entries.first { $0.id == exercise.catalogID }?.profile.actions ?? []
    }

    /// Rows an own exercise carries that match no built-in, read at full weight as search reads them.
    private static func storedActions(of exercise: Exercise, movesLike: [String]) -> [JointAction]? {
        guard movesLike.isEmpty else { return nil }
        let actions = (exercise.jointActions ?? []).compactMap { action in
            action.movement.map { JointAction(movement: $0.key, weight: 1, role: action.role) }
        }
        return actions.isEmpty ? nil : actions
    }

    /// What the lift does at each joint: the catalog's for a built-in, else the lifter's own,
    /// else the `movesLike` lifts' together.
    var jointActions: [JointAction] {
        isBuiltIn ? builtInActions : customActions ?? MovesLike.actions(of: movesLike)
    }

    /// Sets how an own lift uses one worked joint movement, or clears it for nil. The lift then
    /// keeps its own joint actions instead of the `movesLike` lift's.
    mutating func setJoint(_ movement: String, to involvement: JointInvolvement?) {
        guard !isBuiltIn else { return }
        isMovesLikeChosen = true
        customActions = JointInvolvement.setting(movement, to: involvement, in: jointActions)
    }

    /// The picks' names, such as "Lateral Raise, Cable Y Raise", or "Custom" once the lifter set
    /// joint actions by hand. Nil with no pick.
    var movesLikeName: String? {
        if customActions != nil { return "Custom" }
        let names = movesLike.compactMap { MovesLike.entry($0)?.name }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// Whether the form should still propose a lift from the name.
    var wantsMovesLikeProposal: Bool { !isBuiltIn && !isMovesLikeChosen }

    /// A proposal from the name. Ignored once the lifter has chosen.
    mutating func propose(movesLike keys: [String]) {
        guard wantsMovesLikeProposal else { return }
        movesLike = Array(keys.uniqued().prefix(MovesLike.maxPicks))
        suggestSecondaryMuscles()
    }

    /// The lifter's own picks, up to three, or none for None, which keeps the muscles as they are.
    mutating func choose(movesLike keys: [String]) {
        guard !isBuiltIn else { return }
        isMovesLikeChosen = true
        movesLike = Array(keys.uniqued().prefix(MovesLike.maxPicks))
        // Picking lifts, or None, replaces any joint actions set by hand.
        customActions = nil
        if !movesLike.isEmpty { suggestSecondaryMuscles() }
    }

    /// Fills secondary muscles from every `movesLike` pick while the lifter hasn't picked their own.
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

    /// Writes the lifter's joint actions, or else `movesLike`, onto an own exercise in a store,
    /// if either changed since the form opened. `makeExercise()` can't, because the exercise
    /// isn't in a store yet: insert it first.
    func applyMovement(to exercise: Exercise) {
        guard exercise.userCreated, !isBuiltIn,
              movesLike != savedMovesLike || customActions != savedCustomActions,
              let context = exercise.modelContext else { return }
        if let customActions {
            CustomJointActions.write(customActions, to: exercise, in: context)
        } else {
            MovesLike.copy(movesLike, to: exercise, in: context)
        }
    }
}
