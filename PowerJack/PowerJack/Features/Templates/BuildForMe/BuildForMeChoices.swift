//
//  BuildForMeChoices.swift
//  PowerJack
//
//  What the Build for Me form holds, as plain values: every row starts with a default, so Build
//  works right away. The equipment the lifter turns off is remembered between builds.
//

import Foundation

struct BuildForMeChoices: Equatable {
    static let defaultWorkoutsPerWeek = 4
    static let defaultSessionMinutes = 60

    var type: TemplateType
    var workoutsPerWeek = Self.defaultWorkoutsPerWeek
    var focus: [Muscle] = []
    var equipment = EquipmentChoice()
    var sessionMinutes = Self.defaultSessionMinutes
    var lean = TemplateRequest.Lean.mix
    var supersets = false

    var request: TemplateRequest {
        TemplateRequest(
            type: type,
            workoutsPerWeek: workoutsPerWeek,
            focus: focus,
            equipment: TemplateRequest.allEquipment.subtracting(equipment.offKinds),
            missingEquipmentNames: equipment.offPieces,
            setups: TemplateRequest.allSetups.subtracting(equipment.offSetups),
            sessionMinutes: sessionMinutes,
            lean: lean,
            supersets: supersets
        )
    }
}

/// The equipment the lifter turned off. Everything else is on, so a kind added later starts on.
struct EquipmentChoice: Equatable {
    /// Where the choice is kept between builds.
    static let storageKey = "buildForMe.equipmentOff"

    var offKinds: Set<Equipment> = []
    var offSetups: Set<ExerciseFilters.Setup> = []
    /// Named pieces, like an EZ bar or the lifter's own equipment.
    var offPieces: Set<String> = []

    func isOn(_ kind: Equipment) -> Bool { !offKinds.contains(kind) }
    func isOn(_ setup: ExerciseFilters.Setup) -> Bool { !offSetups.contains(setup) }
    func isOn(piece: String) -> Bool { !offPieces.contains(piece) }

    mutating func toggle(_ kind: Equipment) { offKinds.formSymmetricDifference([kind]) }
    mutating func toggle(_ setup: ExerciseFilters.Setup) { offSetups.formSymmetricDifference([setup]) }
    mutating func toggle(piece: String) { offPieces.formSymmetricDifference([piece]) }

    // MARK: Storage

    /// One line per item, like "kind:machine", "setup:bench" or "piece:EZ Bar".
    var stored: String {
        let lines = offKinds.map { "kind:\($0.rawValue)" } + offSetups.map { "setup:\($0.rawValue)" }
            + offPieces.map { "piece:\($0)" }
        return lines.sorted().joined(separator: "\n")
    }

    /// Reads `stored` back. Lines it doesn't know, from a kind since removed, are left out.
    init(stored: String) {
        for line in stored.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "kind": if let kind = Equipment(rawValue: parts[1]) { offKinds.insert(kind) }
            case "setup": if let setup = ExerciseFilters.Setup(rawValue: parts[1]) { offSetups.insert(setup) }
            case "piece": offPieces.insert(parts[1])
            default: break
            }
        }
    }

    init() {}
}
