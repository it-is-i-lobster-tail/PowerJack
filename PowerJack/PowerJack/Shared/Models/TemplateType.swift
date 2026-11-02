//
//  TemplateType.swift
//  PowerJack
//
//  What a template trains for. Picks the Templates section it's listed under
//  and the progression rules a program started from it follows.
//

import Foundation

enum TemplateType: String, Codable, CaseIterable, Identifiable {
    case hypertrophy
    case strength
    case powerJack = "powerjack"

    var id: Self { self }

    /// Where the Templates switcher remembers the chosen section.
    static let selectionKey = "templates.selectedType"

    /// The section name lifters see.
    var name: String {
        switch self {
        case .hypertrophy:
            "Hypertrophy"
        case .strength:
            "Strength"
        case .powerJack:
            "PowerJack"
        }
    }
}
