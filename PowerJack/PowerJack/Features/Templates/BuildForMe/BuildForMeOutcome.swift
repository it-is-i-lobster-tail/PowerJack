//
//  BuildForMeOutcome.swift
//  PowerJack
//
//  Runs the code-only builder for the form's choices, and when the equipment is too thin, says
//  what to turn on.
//

import Foundation

enum BuildForMeOutcome: Equatable {
    case plan(TemplatePlan)
    /// Says why, and names the equipment that would make it work.
    case notEnoughEquipment(String)

    /// Most named items a message suggests turning on.
    private static let suggestions = 3

    init(_ choices: BuildForMeChoices, exercises: [BuilderExercise]) {
        if case .plan(let plan) = PlanBuilder(request: choices.request, exercises: exercises).build() {
            self = .plan(plan)
        } else {
            self = .notEnoughEquipment(Self.message(for: choices, exercises: exercises))
        }
    }

    /// "Not enough equipment to fill 3 exercises a day. Turn on Dumbbell or Bench."
    static func message(for choices: BuildForMeChoices, exercises: [BuilderExercise]) -> String {
        var asHypertrophy = choices
        asHypertrophy.type = .hypertrophy
        let lacksMainLift = choices.type != .hypertrophy && builds(asHypertrophy, exercises)
        let reason = lacksMainLift
            ? "\(choices.type.name) days open with a loaded multi-joint lift, and this equipment has none."
            : "Not enough equipment to fill \(TemplateRules.minimumExercises) exercises a day."

        let fixes = offItems(in: choices.equipment).filter { item in
            var trial = choices
            item.turnOn(&trial.equipment)
            return builds(trial, exercises)
        }
        guard !fixes.isEmpty else { return "\(reason) Turn on more equipment." }
        return "\(reason) Turn on \(fixes.prefix(suggestions).map(\.name).formatted(.list(type: .or)))."
    }

    private static func builds(_ choices: BuildForMeChoices, _ exercises: [BuilderExercise]) -> Bool {
        PlanBuilder(request: choices.request, exercises: exercises).build() != .notEnoughEquipment
    }

    /// Everything turned off, in the order the form shows it.
    private static func offItems(in equipment: EquipmentChoice) -> [EquipmentItem] {
        EquipmentItem.kinds.filter { !equipment.isOn($0) }.map(EquipmentItem.kind)
            + ExerciseFilters.Setup.allCases.filter { !equipment.isOn($0) }.map(EquipmentItem.setup)
            + equipment.offPieces.sorted().map(EquipmentItem.piece)
    }
}

/// One thing the lifter can turn on or off on the form.
enum EquipmentItem: Hashable {
    case kind(Equipment)
    case setup(ExerciseFilters.Setup)
    case piece(String)

    /// The built-in kinds, in the form's order. Loadable bodyweight comes with bodyweight.
    static let kinds: [Equipment] = [.barbell, .dumbbell, .cable, .machine, .legPress, .kettlebell, .bodyweight]

    var name: String {
        switch self {
        case .kind(let kind): kind.displayName
        case .setup(.bench): "Bench"
        case .setup(.pullUpBar): "Pull-up Bar"
        case .piece(let name): name
        }
    }

    func turnOn(_ equipment: inout EquipmentChoice) {
        switch self {
        case .kind(let kind): equipment.offKinds.remove(kind)
        case .setup(let setup): equipment.offSetups.remove(setup)
        case .piece(let name): equipment.offPieces.remove(name)
        }
    }
}
