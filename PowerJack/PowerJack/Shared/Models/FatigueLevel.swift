//
//  FatigueLevel.swift
//  PowerJack
//
//  How much systemic fatigue an exercise causes, whatever weight is on the bar.
//

import Foundation

enum FatigueLevel: String, Codable, CaseIterable, Identifiable {
    // Raw values predate the rename and are what older stores hold, so never change them.
    case low = "light"
    case moderate = "medium"
    case high = "heavy"

    var id: Self { self }

    var name: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }

    /// More fatigue needs a longer rest before the next set.
    var restLength: RestLength {
        switch self {
        case .low: .short
        case .moderate: .standard
        case .high: .long
        }
    }
}
