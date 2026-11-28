//
//  LoadGrid.swift
//  PowerJack
//
//  The loads a lifter can actually put on the bar (rule 1.1): whole load steps in their unit,
//  on top of the empty bar for barbells, or only the weights they own. The engine works in kilograms and rounds here.
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
        case (.loadableBodyweight, .kilograms): [1, 1.25, 2.5, 5]
        case (.loadableBodyweight, .pounds): [2.5, 5, 10]
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
        case (.loadableBodyweight, .kilograms): 2.5
        case (.loadableBodyweight, .pounds): 5
        case (.bodyweight, _): nil
        }
    }

    /// Take the place of the steps picked in Settings within one task, as `WeightUnit.pinned` does for the unit.
    /// Equipment left out uses its default.
    @TaskLocal static var pinned: [Equipment: Double]?

    /// The step picked in Settings, or the default. `nil` for bodyweight, which has no load.
    static func step(for equipment: Equipment, in unit: WeightUnit) -> Double? {
        if let pinned { return pinned[equipment] ?? defaultStep(for: equipment, in: unit) }
        let saved = UserDefaults.standard.double(forKey: key(for: equipment, in: unit))
        return saved > 0 ? saved : defaultStep(for: equipment, in: unit)
    }

    static func key(for equipment: Equipment, in unit: WeightUnit) -> String {
        "settings.strength.loadStep.\(unit.rawValue).\(equipment.rawValue)"
    }
}

extension Equipment {
    /// Bodyweight alone has no load, so it has no load step.
    var hasLoadStep: Bool { StrengthLoadSteps.defaultStep(for: self, in: .pounds) != nil }
}

/// How one kind of equipment loads: even steps on top of each other, or only the weights the lifter owns.
enum LoadMode: String, CaseIterable, Identifiable {
    case evenSteps
    case ownedWeights

    var id: Self { self }

    var title: String {
        switch self {
        case .evenSteps: "Even Steps"
        case .ownedWeights: "Only These Weights"
        }
    }
}

/// The weights a lifter owns for one kind of equipment, kept apart in each unit, like the load steps.
/// Saved as plain strings so the watch and older versions read them without anything new stored in SwiftData.
enum OwnedLoads {
    /// Take the place of the saved choices within one task, as `StrengthLoadSteps.pinned` does.
    /// Equipment left out uses even steps.
    @TaskLocal static var pinned: [Equipment: [Double]]?

    static func mode(for equipment: Equipment, in unit: WeightUnit) -> LoadMode {
        if let pinned { return pinned[equipment] == nil ? .evenSteps : .ownedWeights }
        return UserDefaults.standard.string(forKey: modeKey(for: equipment, in: unit)).flatMap(LoadMode.init) ?? .evenSteps
    }

    /// The saved weights, lightest first, whatever the mode.
    static func weights(for equipment: Equipment, in unit: WeightUnit) -> [Double] {
        if let pinned { return sorted(pinned[equipment] ?? [], in: unit) }
        return decode(UserDefaults.standard.string(forKey: weightsKey(for: equipment, in: unit)) ?? "", in: unit)
    }

    /// The weights loads snap to, or `nil` when the equipment uses even steps or has no weights listed.
    static func active(for equipment: Equipment, in unit: WeightUnit) -> [Double]? {
        guard equipment.hasLoadStep, mode(for: equipment, in: unit) == .ownedWeights else { return nil }
        let weights = weights(for: equipment, in: unit)
        return weights.isEmpty ? nil : weights
    }

    static func modeKey(for equipment: Equipment, in unit: WeightUnit) -> String {
        "settings.strength.loadMode.\(unit.rawValue).\(equipment.rawValue)"
    }

    static func weightsKey(for equipment: Equipment, in unit: WeightUnit) -> String {
        "settings.strength.ownedLoads.\(unit.rawValue).\(equipment.rawValue)"
    }

    /// e.g. "16,24,32". Numbers are written the same way in every locale.
    static func encode(_ weights: [Double]) -> String {
        weights.map { String($0) }.joined(separator: ",")
    }

    /// Weights over what a set can log, zero or negative, and repeats are dropped.
    static func decode(_ text: String, in unit: WeightUnit) -> [Double] {
        sorted(text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }, in: unit)
    }

    static func sorted(_ weights: [Double], in unit: WeightUnit) -> [Double] {
        Array(Set(weights.filter { $0 > 0 && $0 <= unit.maxEntry })).sorted()
    }
}

struct LoadGrid: Equatable {
    /// The empty bar, which barbell loads never go under (rule 1.1).
    static let barKilograms = 20.0
    static let barPounds = 45.0
    /// The most a set can log, 1,000 lb, which plans never go over (rule 1.1).
    static let capKilograms = Double(WorkoutSet.maxWeightPounds) * WeightUnit.kilogramsPerPound
    /// Sets store tenths of a pound, so a logged load can sit this far from the grid load it was planned at.
    static let storedTolerance = 0.05 * WeightUnit.kilogramsPerPound

    let unit: WeightUnit
    /// In `unit`. Zero for a list of owned weights.
    let step: Double
    /// Barbells count steps up from the bar; everything else from zero.
    let base: Double
    /// Loadable bodyweight starts at no added weight at all.
    let startsAtZero: Bool
    /// Only these loads, in kilograms, lightest first, when the lifter listed the weights they own.
    let owned: [Double]?

    init(unit: WeightUnit, step: Double, isBarbell: Bool, startsAtZero: Bool = false) {
        self.unit = unit
        self.step = step
        self.base = isBarbell ? (unit == .kilograms ? Self.barKilograms : Self.barPounds) : 0
        self.startsAtZero = startsAtZero && !isBarbell
        owned = nil
    }

    /// Only `weights`, in `unit`. The list holds whole loads, so a barbell's are bar and plates together.
    /// Loadable bodyweight can also go back to no added weight.
    init(unit: WeightUnit, owned weights: [Double], startsAtZero: Bool = false) {
        self.unit = unit
        step = 0
        base = 0
        self.startsAtZero = startsAtZero
        let loads = OwnedLoads.sorted(weights, in: unit).map { $0 * unit.kilograms }
        owned = (startsAtZero ? [0] : []) + loads
    }

    /// The grid for `equipment` with the choices made in My Gym: the owned weights, or the load step. `nil` for bodyweight.
    init?(equipment: Equipment, unit: WeightUnit = .current) {
        if let weights = OwnedLoads.active(for: equipment, in: unit) {
            self.init(unit: unit, owned: weights, startsAtZero: equipment == .loadableBodyweight)
            return
        }
        guard let step = StrengthLoadSteps.step(for: equipment, in: unit) else { return nil }
        self.init(unit: unit, step: step, isBarbell: equipment == .barbell, startsAtZero: equipment == .loadableBodyweight)
    }

    var stepKilograms: Double { step * unit.kilograms }
    /// The lightest load: the bar, one step, the lightest owned weight, or none for loadable bodyweight.
    var minimumKilograms: Double {
        if let owned { return owned.first ?? 0 }
        return (base > 0 ? base : startsAtZero ? 0 : step) * unit.kilograms
    }
    /// The heaviest grid load a set can log.
    var maximumKilograms: Double {
        if let owned { return owned.last ?? 0 }
        return (base + (stepsFromBase(Self.capKilograms) + Self.tolerance).rounded(.down) * step) * unit.kilograms
    }

    /// Nearest grid load, ties going down (rule 1.1).
    func nearest(_ kilograms: Double) -> Double {
        if let owned {
            return owned.min { abs($0 - kilograms) < abs($1 - kilograms) - Self.tolerance } ?? kilograms
        }
        let steps = stepsFromBase(kilograms)
        let lower = steps.rounded(.down)
        return load(steps - lower > 0.5 + Self.tolerance ? lower + 1 : lower)
    }

    /// Highest grid load at or under `kilograms`, or the lightest when every load is heavier.
    func down(_ kilograms: Double) -> Double {
        if let owned {
            return owned.last { $0 <= kilograms + Self.tolerance } ?? minimumKilograms
        }
        return load((stepsFromBase(kilograms) + Self.tolerance).rounded(.down))
    }

    /// A share of a load, as back-off sets, deloads and warm-ups take: the nearest load on even steps,
    /// and the owned weight at or under it (or the lightest) on a list, so it never ends up heavier than planned.
    func share(_ kilograms: Double) -> Double {
        owned == nil ? nearest(kilograms) : down(kilograms)
    }

    /// The lightest grid load at or over `kilograms`, or `nil` past the heaviest.
    func up(_ kilograms: Double) -> Double? {
        if let owned { return owned.first { $0 >= kilograms - Self.tolerance } }
        let load = load((stepsFromBase(kilograms) - Self.tolerance).rounded(.up))
        return load >= kilograms - Self.tolerance ? load : nil
    }

    /// `kilograms` moved by whole steps, on the grid. With owned weights a step is the next weight on the list.
    func moved(_ kilograms: Double, bySteps steps: Int) -> Double {
        if let owned {
            let near = nearest(kilograms)
            guard let index = owned.firstIndex(of: near) else { return near }
            return owned[min(max(index + steps, 0), owned.count - 1)]
        }
        return load(stepsFromBase(nearest(kilograms)).rounded() + Double(steps))
    }

    /// How far the next heavier load sits above `kilograms`, or zero at the heaviest.
    func stepKilograms(above kilograms: Double) -> Double {
        guard owned != nil else { return stepKilograms }
        return up(kilograms + Self.tolerance * 2).map { $0 - kilograms } ?? 0
    }

    /// One step is more than `StrengthRules.maxStepShare` of the load, so reps rise before load (rule 1.2).
    /// On the heaviest owned weight there's no step left, so only reps can rise.
    func isCoarse(at kilograms: Double) -> Bool {
        guard kilograms > 0 else { return false }
        guard owned != nil else { return stepKilograms > StrengthRules.maxStepShare * kilograms }
        let step = stepKilograms(above: kilograms)
        return step == 0 || step > StrengthRules.maxStepShare * kilograms
    }

    private static let tolerance = 1e-6

    private func stepsFromBase(_ kilograms: Double) -> Double {
        (kilograms / unit.kilograms - base) / step
    }

    private func load(_ steps: Double) -> Double {
        min(maximumKilograms, max(minimumKilograms, (base + steps * step) * unit.kilograms))
    }
}
