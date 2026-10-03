//
//  Fatigue.swift
//  PowerJack
//
//  How hard an exercise is to recover from, which sets the rest before its next set.
//

import Foundation

enum Fatigue: String, Codable, CaseIterable, Identifiable {
    case light
    case medium
    case heavy

    var id: Self { self }

    var restDuration: Duration {
        switch self {
        case .light: .seconds(75)
        case .medium: .seconds(135)
        case .heavy: .seconds(180)
        }
    }
}
