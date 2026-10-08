//
//  RestSettingsHint.swift
//  PowerJack
//

import SwiftUI

/// Shown on Start Workout before week 2, day 2.
struct RestSettingsHint: Hint {
    var title: Text { Text("Rest timers too short or too long?") }
    var message: Text? { Text("Change them in Settings.") }
}
