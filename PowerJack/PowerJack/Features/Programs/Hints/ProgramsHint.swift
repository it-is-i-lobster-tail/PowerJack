//
//  ProgramsHint.swift
//  PowerJack
//

import SwiftUI
import TipKit

/// Shown at the top of Programs once the lifter taps Programs, until they open one.
struct ProgramsHint: Hint {
    /// Donated when the lifter taps Programs in the switcher.
    static let opened = Tips.Event(id: "programsOpened")

    var title: Text { Text("Programs are a plan in action.") }
    var message: Text? { Text("Work through a program and progress week over week.") }
    var extraRules: [Rule] { [#Rule(Self.opened) { $0.donations.count >= 1 }] }
}
