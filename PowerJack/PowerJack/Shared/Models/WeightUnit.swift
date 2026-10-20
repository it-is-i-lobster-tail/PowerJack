//
//  WeightUnit.swift
//  PowerJack
//
//  The unit weights are shown and typed in. Sets always store tenths of a pound,
//  so changing the unit converts what is shown and never changes what was logged.
//

import Foundation

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case pounds = "lb"
    case kilograms = "kg"

    static let kilogramsPerPound = 0.45359237

    var id: Self { self }

    var symbol: String { rawValue }

    var name: String {
        switch self {
        case .pounds: "Pounds"
        case .kilograms: "Kilograms"
        }
    }

    /// Takes the place of the Settings pick within one task. Settings are shared by every test running at once,
    /// so tests that need a unit pin it here instead.
    @TaskLocal static var pinned: WeightUnit?

    /// The unit picked in Settings, or the device's measurement system until one is picked.
    static var current: WeightUnit {
        pinned ?? UserDefaults.standard.string(forKey: AppSettings.Key.weightUnit)
            .flatMap(WeightUnit.init(rawValue:)) ?? deviceDefault
    }

    static var deviceDefault: WeightUnit {
        Locale.current.measurementSystem == .us ? .pounds : .kilograms
    }

    /// One unit in kilograms.
    var kilograms: Double {
        switch self {
        case .pounds: Self.kilogramsPerPound
        case .kilograms: 1
        }
    }

    /// The heaviest weight a set can log, in this unit.
    var maxEntry: Double {
        switch self {
        case .pounds: Double(WorkoutSet.maxWeightPounds)
        case .kilograms: (Double(WorkoutSet.maxWeightPounds) * Self.kilogramsPerPound).rounded(.down)
        }
    }

    func value(fromTenthsPounds tenths: Int) -> Double {
        Double(tenths) / 10 * Self.kilogramsPerPound / kilograms
    }

    func tenthsPounds(from value: Double) -> Int {
        Int((value * kilograms / Self.kilogramsPerPound * 10).rounded())
    }

    /// e.g. "102.5" in kilograms or "225" in pounds, without the unit.
    func format(tenthsPounds tenths: Int) -> String {
        value(fromTenthsPounds: tenths).formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    static func kilograms(fromTenthsPounds tenths: Int) -> Double {
        Double(tenths) / 10 * kilogramsPerPound
    }

    static func tenthsPounds(fromKilograms kilograms: Double) -> Int {
        Int((kilograms / kilogramsPerPound * 10).rounded())
    }
}
