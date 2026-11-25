//
//  Equipment.swift
//  PowerJack
//
//  Created on 6/24/26.
//

import Foundation
import SwiftData

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case barbell
    case dumbbell
    case bodyweight
    /// Bodyweight work that can take added weight, like weighted pull-ups. A weight of 0 is bodyweight alone.
    /// Never stored as is: older versions can't read it, so `Exercise` stores it as `.bodyweight` plus a flag.
    case loadableBodyweight
    case cable
    case machine
    case kettlebell
    case legPress

    var id: Self { self }

    nonisolated var displayName: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .bodyweight: "Bodyweight"
        case .loadableBodyweight: "Loadable Bodyweight"
        case .cable: "Cable"
        case .machine: "Machine"
        case .kettlebell: "Kettlebell"
        case .legPress: "Leg Press"
        }
    }
}

/// User-defined equipment inherits the loading rules of a built-in type.
@Model
final class CustomEquipment {
    static let nameLimit = 16
    var name: String = ""
    var base: Equipment = Equipment.machine

    init(name: String, base: Equipment) {
        self.name = name
        self.base = base
    }
}
