//
//  BaselineHint.swift
//  PowerJack
//

import SwiftUI

/// Shown on Start Workout before a week 1 workout.
struct BaselineHint: Hint {
    let occasion: HintOccasion?
    /// Programs that rate reps left show each exercise's own aim, which can differ from 2.
    var ratesRepsInReserve = false

    var title: Text { Text("Week 1 sets your baseline") }
    var message: Text? {
        ratesRepsInReserve
            ? Text("Each exercise shows how many reps to leave in the tank.")
            : Text("Pick weights that leave about 2 reps in the tank.")
    }
}
