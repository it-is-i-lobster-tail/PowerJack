//
//  SupersetStyle.swift
//  PowerJack
//
//  How supersets look everywhere they're shown: one color per letter, and a short label
//  when the full list of partners would be too long to read at a glance.
//

import SwiftUI

enum SupersetStyle {
    /// A day has at most five supersets, A to E, one for each color.
    static let maxPerWorkout = 5

    /// Shown where New Superset would be, once a day has all five.
    static let limitNote = "A day can have up to 5 supersets."

    /// A, B, C, D, E. Older days with more than five cycle back through them.
    static let colors: [Color] = [.blue, .purple, .teal, .orange, .pink]

    /// The color of the superset at `index`: 0 for A, 1 for B, and so on.
    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }

    /// Longer than this, "Superset with …" becomes just "Superset B".
    static let maxLabelLength = 45

    /// e.g. "Superset with Skull Crusher", or "Superset B" when the names don't fit.
    static func label(letter: String, partners: [String]) -> String {
        let full = fullLabel(partners: partners)
        return full.count > maxLabelLength ? "Superset \(letter)" : full
    }

    /// Every partner's name, for VoiceOver and anywhere there's room.
    static func fullLabel(partners: [String]) -> String {
        "Superset with \(partners.formatted(.list(type: .and)))"
    }
}
