//
//  SwapExerciseHint.swift
//  PowerJack
//

import SwiftUI

/// Shown on Start Workout before week 2, day 1.
struct SwapExerciseHint: Hint {
    var title: Text { Text("Swap any exercise for the rest of your program.") }
    var message: Text? { Text("Or substitute one just for a workout. Find the best exercises for you.") }
}
