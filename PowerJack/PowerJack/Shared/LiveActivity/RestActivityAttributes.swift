//
//  RestActivityAttributes.swift
//  PowerJack
//
//  The workout Live Activity shown in the Dynamic Island and on the Lock Screen:
//  the current set, its target, and the rest before it.
//  Compiled into the widget extension too, along with everything else in this file.
//

import ActivityKit
import AppIntents
import Foundation

nonisolated struct RestActivityAttributes: ActivityAttributes, Hashable {
    typealias ContentState = WorkoutActivityState

    /// e.g. "Day 2 · Week 1". A different workout gets its own activity.
    var workoutTitle: String

    /// Opens PowerJack on the current exercise of the active workout.
    static let currentExerciseURL = URL(string: "powerjack://workout/current")!
}

/// The set to do next and, between sets of an exercise, the rest before it.
nonisolated struct WorkoutActivityState: Codable, Hashable {
    var exerciseName: String
    /// `order` of the set's exercise and of the set, so a check completes the set that was shown.
    var exerciseOrder: Int
    var setOrder: Int
    var setCount: Int
    /// `nil` when there is no target yet, e.g. in week 1 or for a newly added exercise.
    var targetReps: Int?
    var targetWeightTenthsPounds: Int?
    var repsOnly: Bool
    /// The set can be checked off at its target without opening the app.
    var canCompleteAtTarget: Bool
    /// `nil` when no rest is running, e.g. at the start of a workout or of a new exercise.
    var rest: ClosedRange<Date>?

    var setText: String { "Set \(setOrder + 1) of \(setCount)" }

    var targetRepsText: String {
        targetReps.map(String.init) ?? "–"
    }

    var targetWeightText: String {
        if repsOnly { return "BW" }
        guard let targetWeightTenthsPounds else { return "–" }
        let pounds = Double(targetWeightTenthsPounds) / 10
        return pounds.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// The check button: logs the shown set at its target weight and reps.
/// Live Activity intents run in the app, so `perform()` lives in CompleteSetIntent+App.swift;
/// the widget's copy only lets it build the button.
struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Set at Target"
    static let isDiscoverable = false

    @Parameter(title: "Exercise")
    var exerciseOrder: Int

    @Parameter(title: "Set")
    var setOrder: Int

    init() {}

    init(exerciseOrder: Int, setOrder: Int) {
        self.exerciseOrder = exerciseOrder
        self.setOrder = setOrder
    }
}
