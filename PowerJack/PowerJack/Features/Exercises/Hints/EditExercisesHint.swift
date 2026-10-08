//
//  EditExercisesHint.swift
//  PowerJack
//

import SwiftUI

/// Shown on Start Workout before week 3, day 1.
struct EditExercisesHint: Hint {
    var title: Text { Text("You can edit any exercise to better suit your needs.") }
    var message: Text? { Text("That includes ideal rep ranges and how long to rest.") }
}
