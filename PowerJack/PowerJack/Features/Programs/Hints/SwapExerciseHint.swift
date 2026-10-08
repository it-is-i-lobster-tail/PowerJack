//
//  SwapExerciseHint.swift
//  PowerJack
//

import SwiftUI

/// Shown on Start Workout before week 2, day 1.
struct SwapExerciseHint: Hint {
    var title: Text { Text("You can swap any exercise mid-week.") }
    var message: Text? { Text("Find the best exercises for you.") }
}
