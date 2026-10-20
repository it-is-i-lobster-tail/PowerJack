//
//  LoadGrid.swift
//  PowerJack
//
//  The loads a lifter can actually put on the bar (rule 1.1): whole load steps in their unit,
//  on top of the empty bar for barbells. The engine works in kilograms and rounds here.
//

import Foundation

/// The smallest load change per equipment type for Strengthen, set apart in each unit (rule 1.5).
enum StrengthLoadSteps {
    /// Choices offered in Settings, in the unit's own numbers. The default is marked by `defaultStep`.
    static func options(for equipment: Equipment, in unit: WeightUnit) -> [Double] {
        switch (equipment, unit) {
        case (.barbell, .kilograms): [0.5, 1, 1.25, 2, 2.5, 5]
        case (.barbell, .pounds): [1, 2, 2.5, 5, 10]
        case (.dumbbell, .kilograms): [0.5, 1, 1.25, 2, 2.5]
        case (.dumbbell, .pounds): [1, 2, 2.5, 5]
        case (.cable, .kilograms), (.machine, .kilograms): [1, 2, 2.5, 5, 10]
        case (.cable, .pounds), (.machine, .pounds): [2.5, 5, 10, 15, 20]
        case (.legPress, .kilograms): [2.5, 5, 10, 20]
        case (.legPress, .pounds): [5, 10, 20, 45]
        case (.kettlebell, .kilograms): [2, 4, 8]
        case (.kettlebell, .pounds): [5, 10, 15, 20]
        case (.bodyweight, _): []
        }
    }

    static func defaultStep(for equipment: Equipment, in unit: WeightUnit) -> Double? {
        switch (equipment, unit) {
        case (.barbell, .kilograms): 2.5
        case (.barbell, .pounds): 5
        case (.dumbbell, .kilograms): 2
        case (.dumbbell, .pounds): 5
        case (.cable, .kilograms), (.machine, .kilograms), (.legPress, .kilograms): 5
        case (.cable, .pounds), (.machine, .pounds), (.legPress, .pounds): 10
        case (.kettlebell, .kilograms): 4
        case (.kettlebell, .pounds): 10
        case (.bodyweight, _): nil
        }
    }

    /// The step picked in Settings, or the default. `nil` for bodyweight, which has no load.
    static func step(for equipment: Equipment, in unit: WeightUnit) -> Double? {
        let saved = UserDefaults.standard.double(forKey: key(for: equipment, in: unit))
        return saved > 0 ? saved : defaultStep(for: equipment, in: unit)
    }

    static func key(for equipment: Equipment, in unit: WeightUnit) -> String {
        "settings.strength.loadStep.\(unit.rawValue).\(equipment.rawValue)"
    }
}

struct LoadGrid: Equatable {
    /// The empty bar, which barbell loads never go under (rule 1.1).
    static let barKilograms = 20.0
    static let barPounds = 45.0

    let unit: WeightUnit
    /// In `unit`.
    let step: Double
    /// Barbells count steps up from the bar; everything else from zero.
    let base: Double

    init(unit: WeightUnit, step: Double, isBarbell: Bool) {
        self.unit = unit
        self.step = step
        self.base = isBarbell ? (unit == .kilograms ? Self.barKilograms : Self.barPounds) : 0
    }

    /// The grid for `equipment` with the steps picked in Settings. `nil` for bodyweight.
    init?(equipment: Equipment, unit: WeightUnit = .current) {
        guard let step = StrengthLoadSteps.step(for: equipment, in: unit) else { return nil }
        self.init(unit: unit, step: step, isBarbell: equipment == .barbell)
    }

    var stepKilograms: Double { step * unit.kilograms }
    /// The lightest load: the bar, or one step.
    var minimumKilograms: Double { (base > 0 ? base : step) * unit.kilograms }

    /// Nearest grid load, ties going down (rule 1.1).
    func nearest(_ kilograms: Double) -> Double {
        let steps = stepsFromBase(kilograms)
        let lower = steps.rounded(.down)
        return load(steps - lower > 0.5 + Self.tolerance ? lower + 1 : lower)
    }

    /// Highest grid load at or under `kilograms`.
    func down(_ kilograms: Double) -> Double {
        load((stepsFromBase(kilograms) + Self.tolerance).rounded(.down))
    }

    /// `kilograms` moved by whole steps, on the grid.
    func moved(_ kilograms: Double, bySteps steps: Int) -> Double {
        load(stepsFromBase(nearest(kilograms)).rounded() + Double(steps))
    }

    /// One step is more than `StrengthRules.maxStepShare` of the load, so reps rise before load (rule 1.2).
    func isCoarse(at kilograms: Double) -> Bool {
        kilograms > 0 && stepKilograms > StrengthRules.maxStepShare * kilograms
    }

    private static let tolerance = 1e-6

    private func stepsFromBase(_ kilograms: Double) -> Double {
        (kilograms / unit.kilograms - base) / step
    }

    private func load(_ steps: Double) -> Double {
        max(minimumKilograms, (base + steps * step) * unit.kilograms)
    }
}
