//
//  RestLength.swift
//  PowerJack
//
//  The rest before the next set. Each length's time is set in Settings.
//

import Foundation

enum RestLength: String, CaseIterable, Identifiable {
    case short
    case standard
    case long

    static let range: ClosedRange<Duration> = .seconds(30) ... .seconds(300)
    static let step: Duration = .seconds(5)

    var id: Self { self }

    var name: String {
        switch self {
        case .short: "Short"
        case .standard: "Standard"
        case .long: "Long"
        }
    }

    /// The time set in Settings, or the default when it hasn't been changed.
    var duration: Duration {
        let seconds = UserDefaults.standard.integer(forKey: secondsKey)
        return seconds > 0 ? .seconds(seconds) : defaultDuration
    }

    var defaultDuration: Duration {
        switch self {
        case .short: .seconds(75)
        case .standard: .seconds(135)
        case .long: .seconds(180)
        }
    }

    /// UserDefaults key holding this length in whole seconds.
    var secondsKey: String { "settings.restBetweenSets.\(rawValue)" }
}
