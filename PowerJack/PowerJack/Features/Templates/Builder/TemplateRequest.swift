//
//  TemplateRequest.swift
//  PowerJack
//
//  What the lifter asks Build for Me for. Every value is kept inside the form's limits, so the
//  builder and its rules can trust it.
//

import Foundation

struct TemplateRequest: Hashable, Sendable {
    enum Lean: String, CaseIterable, Sendable {
        case freeWeights, mix, machines
    }

    static let sessionLengths = [45, 60, 75, 90]
    /// Every kind the form offers. Loadable bodyweight comes with bodyweight (`Equipment.covers`).
    static let allEquipment = Set(Equipment.allCases.filter { $0 != .loadableBodyweight })
    static let allSetups = Set(ExerciseFilters.Setup.allCases)
    /// Named pieces the built-in exercises use, like the EZ bar, trap bar and ab wheel.
    static let catalogEquipmentNames = Set(ExerciseCatalog.equipmentOptions.compactMap(\.name))

    let type: TemplateType
    let workoutsPerWeek: Int
    let focus: [Muscle]
    let equipment: Set<Equipment>
    /// Named pieces the lifter doesn't have, like an EZ bar or a trap bar, though they have the kind.
    let missingEquipmentNames: Set<String>
    let setups: Set<ExerciseFilters.Setup>
    let sessionMinutes: Int
    let lean: Lean
    let supersets: Bool

    init(
        type: TemplateType = .hypertrophy,
        workoutsPerWeek: Int = 4,
        focus: [Muscle] = [],
        equipment: Set<Equipment> = Self.allEquipment,
        missingEquipmentNames: Set<String> = [],
        setups: Set<ExerciseFilters.Setup> = Self.allSetups,
        sessionMinutes: Int = 60,
        lean: Lean = .mix,
        supersets: Bool = false
    ) {
        self.type = type
        self.workoutsPerWeek = min(
            max(workoutsPerWeek, TemplateProgramDraft.minimumWorkoutsPerWeek),
            TemplateProgramDraft.maximumWorkoutsPerWeek
        )
        var seen = Set<Muscle>()
        self.focus = Array(focus.filter { seen.insert($0).inserted }.prefix(TemplateProgramDraft.maximumFocusMuscles))
        self.equipment = equipment
        self.missingEquipmentNames = missingEquipmentNames
        self.setups = setups
        // The nearest length the form offers.
        self.sessionMinutes = Self.sessionLengths.min { abs($0 - sessionMinutes) < abs($1 - sessionMinutes) } ?? 60
        self.lean = lean
        self.supersets = supersets
    }

    var sessionSeconds: Int { sessionMinutes * 60 }

    /// True when the lifter has the exercise's equipment, its named piece if it needs one, and every
    /// setup it needs.
    func allows(_ exercise: BuilderExercise) -> Bool {
        equipment.contains { $0.covers(exercise.equipment) }
            && !(exercise.equipmentName.map(missingEquipmentNames.contains) ?? false)
            && exercise.setups.isSubset(of: setups)
    }
}
