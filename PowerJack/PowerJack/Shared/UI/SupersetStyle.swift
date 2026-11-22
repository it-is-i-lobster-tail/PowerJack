//
//  SupersetStyle.swift
//  PowerJack
//
//  How supersets look everywhere they're shown: one color per letter.
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

    /// e.g. "Superset with Skull Crusher", every partner's name for VoiceOver.
    static func fullLabel(partners: [String]) -> String {
        "Superset with \(partners.formatted(.list(type: .and)))"
    }
}
