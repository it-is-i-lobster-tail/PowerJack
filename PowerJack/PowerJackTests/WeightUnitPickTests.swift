//
//  WeightUnitPickTests.swift
//  PowerJackTests
//
//  The unit is saved once at first launch, so the phone's region can never switch it later.
//

import Foundation
import Testing
@testable import PowerJack

@Suite("Weight unit pick")
struct WeightUnitPickTests {
    private let key = AppSettings.Key.weightUnit

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "WeightUnitPickTests.\(UUID().uuidString)"))
    }

    @Test("First launch saves the device's unit, and the watch gets it with the other settings")
    func savesDeviceDefaultWhenNothingIsSaved() throws {
        let defaults = try makeDefaults()

        WeightUnit.saveDeviceDefaultIfUnpicked(in: defaults)

        #expect(defaults.string(forKey: key) == WeightUnit.deviceDefault.rawValue)
        #expect(SettingsSync(defaults: defaults).settings[key] as? String == WeightUnit.deviceDefault.rawValue)
    }

    @Test("A saved pick is never overwritten", arguments: WeightUnit.allCases)
    func keepsSavedPick(_ unit: WeightUnit) throws {
        let defaults = try makeDefaults()
        defaults.set(unit.rawValue, forKey: key)

        WeightUnit.saveDeviceDefaultIfUnpicked(in: defaults)
        WeightUnit.saveDeviceDefaultIfUnpicked(in: defaults)

        #expect(defaults.string(forKey: key) == unit.rawValue)
    }

    @Test("An unreadable value counts as no pick and is replaced")
    func replacesUnreadableValue() throws {
        let defaults = try makeDefaults()
        defaults.set("stone", forKey: key)

        WeightUnit.saveDeviceDefaultIfUnpicked(in: defaults)

        #expect(defaults.string(forKey: key) == WeightUnit.deviceDefault.rawValue)
    }
}
