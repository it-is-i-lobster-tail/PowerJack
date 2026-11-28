//
//  BuilderExercise.swift
//  PowerJack
//
//  A plain copy of an exercise with only what Build for Me reads, so the builder and its rules
//  run without SwiftData. The builder never changes an exercise.
//

import Foundation

struct BuilderExercise: Identifiable, Hashable, Sendable {
    enum Direction: Sendable {
        case push, pull
    }

    /// `StrengthLifts.key(for:)`: the catalog ID, or a key the lifter's own exercise keeps for good.
    let id: String
    let name: String
    let catalogID: String?
    let equipment: Equipment
    /// A named piece of its equipment kind, like a trap bar or the lifter's own, that not every gym has.
    let equipmentName: String?
    let primary: Muscle
    let secondaries: [Muscle]
    let fatigue: FatigueLevel
    let pattern: MovementPattern?
    /// Rest between sets: the fatigue level's, or the exercise's own rest time.
    let restSeconds: Int
    /// Bench or pull-up bar the lift needs, read from its name the way search reads it.
    let setups: Set<ExerciseFilters.Setup>
    /// How many times the lifter has done it, for ranking.
    let uses: Int
    /// Works more than its main muscle through more than one joint.
    let isCompound: Bool
    /// Loaded and multi-joint, so a Strength program can make it a priority lift (`StrengthLifts.isCompound`).
    let isStrengthMainLift: Bool
    /// Squat, hinge, push or pull, as the PowerJack engine reads it. Nil for single-joint work.
    let liftPattern: PowerJackPattern?
    /// The pattern it can be the PowerJack main lift of (`PowerJackExercise.isMainLiftEligible`).
    let powerJackMainPattern: PowerJackPattern?

    init(
        id: String,
        name: String,
        catalogID: String? = nil,
        equipment: Equipment,
        equipmentName: String? = nil,
        primary: Muscle,
        secondaries: [Muscle] = [],
        fatigue: FatigueLevel,
        pattern: MovementPattern?,
        restSeconds: Int? = nil,
        uses: Int = 0
    ) {
        self.id = id
        self.name = name
        self.catalogID = catalogID
        self.equipment = equipment
        self.equipmentName = equipmentName
        self.primary = primary
        self.secondaries = secondaries.sorted { $0.rawValue < $1.rawValue }
        self.fatigue = fatigue
        self.pattern = pattern
        self.restSeconds = restSeconds ?? Int(fatigue.restLength.defaultDuration.components.seconds)
        self.setups = Set(ExerciseFilters.Setup.allCases.filter { $0.isUsed(by: ExerciseQuery.words(name)) })
        self.uses = uses

        let traits = PowerJackExercise.traits(catalogID: catalogID, primary: primary, fatigue: fatigue)
        let powerJack = PowerJackExercise(
            id: AnyHashable(id),
            pattern: traits.0,
            multiJoint: traits.1,
            repsOnly: equipment == .bodyweight,
            addsToBodyweight: equipment == .loadableBodyweight,
            fatigue: fatigue,
            primary: primary,
            secondaries: secondaries
        )
        self.isCompound = traits.1 || secondaries.count >= 2
        self.isStrengthMainLift = equipment != .bodyweight && equipment != .loadableBodyweight && secondaries.count >= 2
        self.liftPattern = traits.0
        self.powerJackMainPattern = powerJack.isMainLiftEligible ? traits.0 : nil
    }

    init(_ exercise: Exercise, uses: Int = 0) {
        self.init(
            id: StrengthLifts.key(for: exercise),
            name: exercise.exerciseName,
            catalogID: exercise.catalogID,
            equipment: exercise.equipment,
            equipmentName: exercise.customEquipmentName,
            primary: exercise.primaryMuscleFocus,
            secondaries: exercise.secondaryMuscles,
            fatigue: exercise.fatigueLevel,
            pattern: exercise.movementPattern,
            restSeconds: Int(exercise.restDuration.components.seconds),
            uses: uses
        )
    }

    init(_ entry: ExerciseCatalog.Entry) {
        self.init(
            id: entry.id,
            name: entry.name,
            catalogID: entry.id,
            equipment: entry.equipment,
            equipmentName: entry.equipmentName,
            primary: entry.primaryMuscle,
            secondaries: entry.secondaryMuscles,
            fatigue: entry.fatigueLevel,
            pattern: entry.profile.pattern
        )
    }

    /// The built-in exercises as they are seeded.
    static let catalog = ExerciseCatalog.entries.map { BuilderExercise($0) }
}

extension BuilderExercise {
    /// Low or Moderate single-joint work: what can share a superset.
    var isAccessory: Bool { !isCompound && fatigue != .high }

    /// A lift that wants warmup sets before it.
    var isBigLift: Bool { fatigue == .high || isStrengthMainLift }

    /// Pressing or pulling with the upper body, by movement pattern. Lifts with no pattern read from
    /// their main muscle.
    var direction: Direction? {
        switch pattern {
        case .horizontalPress, .overheadPress, .dip, .chestFly: .push
        case .verticalPull, .horizontalPull, .reverseFly, .facePull: .pull
        case nil: primary == .chest ? .push : primary == .back ? .pull : nil
        default: nil
        }
    }
}
