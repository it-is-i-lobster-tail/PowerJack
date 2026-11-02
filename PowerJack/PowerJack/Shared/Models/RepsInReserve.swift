//
//  RepsInReserve.swift
//  PowerJack
//
//  The effort tap: how many more good reps the lifter could have done on an exercise's last set.
//

import Foundation

enum RepsInReserve: Int, Codable, CaseIterable, Identifiable, ScaleSelectorOption {
    case zero = 0
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    /// Five or more. Read as 5, and only ever a lower bound.
    case fiveOrMore = 5

    /// `ExerciseFeedback.effortScaleVersion` for ratings on this scale. Version 1 is `LevelOfEffort`.
    static let scaleVersion = 2

    var id: Self { self }

    var valueText: String { self == .fiveOrMore ? "5+" : "\(rawValue)" }

    var label: String {
        switch self {
        case .zero: "No reps left"
        case .one: "1 rep left"
        case .two, .three, .four: "\(rawValue) reps left"
        case .fiveOrMore: "5 or more"
        }
    }

    /// Kept in `ExerciseFeedback`'s existing 0-5 effort field as 5 minus reps left.
    var storedValue: Int { 5 - rawValue }

    init?(storedValue: Int) {
        self.init(rawValue: 5 - storedValue)
    }
}
