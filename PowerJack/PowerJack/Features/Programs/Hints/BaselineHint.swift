//
//  BaselineHint.swift
//  PowerJack
//

import SwiftUI

/// Shown on Start Workout before a week 1 workout.
struct BaselineHint: Hint {
    let occasion: HintOccasion?

    var title: Text { Text("Week 1 sets your baseline") }
    var message: Text? { Text("Pick weights that leave about 2 reps in the tank.") }
}
