//
//  RestActivityAttributes.swift
//  PowerJack
//
//  The rest timer Live Activity shown in the Dynamic Island and on the Lock Screen.
//  Compiled into the widget extension too.
//

import ActivityKit
import Foundation

nonisolated struct RestActivityAttributes: ActivityAttributes, Hashable {
    typealias ContentState = RestPeriod

    /// e.g. "Day 2 · Week 1". A different workout gets its own activity.
    var workoutTitle: String

    /// Opens PowerJack on the current exercise of the active workout.
    static let currentExerciseURL = URL(string: "powerjack://workout/current")!
}
