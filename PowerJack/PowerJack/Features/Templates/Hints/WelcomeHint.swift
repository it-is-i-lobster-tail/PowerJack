//
//  WelcomeHint.swift
//  PowerJack
//

import SwiftUI

/// Points at Templates the first time the app opens.
struct WelcomeHint: Hint {
    var title: Text { Text("Welcome to PowerJack") }
    var message: Text? { Text("To start, view your templates.") }
}
