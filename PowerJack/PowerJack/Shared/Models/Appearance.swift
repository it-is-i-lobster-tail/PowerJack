//
//  Appearance.swift
//  PowerJack
//
//  Light or dark. System follows the iPhone, so it switches on its own between day and night.
//

import UIKit

enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The style to force, or unspecified to follow the iPhone.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

// Here rather than in AppSettings, which the watch shares and which can't see this iPhone-only type.
extension AppSettings.Default {
    static let appearance = Appearance.system
}
