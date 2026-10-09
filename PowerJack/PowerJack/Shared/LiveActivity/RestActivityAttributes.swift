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

/// Every set of the current exercise and, between sets, the rest before the next one.
nonisolated struct WorkoutActivityState: Codable, Hashable {
    var exerciseName: String
    /// e.g. "Warmup 1 of 2" or "Set 2 of 3". Warmups are numbered apart from working sets, as in the app.
    var setText: String
    /// `order` of the set's exercise and of the current set, so a check completes the set that was shown.
    var exerciseOrder: Int
    var setOrder: Int
    var sets: [ActivitySet]
    var repsOnly: Bool
    /// The current set can be checked off at its target without opening the app.
    var canCompleteAtTarget: Bool
    /// `nil` when no rest is running, e.g. at the start of a workout or of a new exercise.
    var rest: ClosedRange<Date>?

    /// "Warmup 1 of 2" or "Set 1 of 2". Shared with the in-app rest island so both read the same.
    static func setText(number: Int, count: Int, isWarmup: Bool) -> String {
        "\(isWarmup ? "Warmup" : "Set") \(number) of \(count)"
    }
}

/// One set as the Live Activity shows it: what was logged once done, its target until then.
nonisolated struct ActivitySet: Codable, Hashable {
    enum Progress: String, Codable {
        case done, skipped, current, upcoming
    }

    /// "W1" for a warmup, "1" for a working set.
    var label: String
    var progress: Progress
    /// `nil` when there is nothing to show yet, e.g. no target in week 1.
    var reps: Int?
    var weightTenthsPounds: Int?

    var repsText: String {
        reps.map(String.init) ?? "–"
    }

    func weightText(repsOnly: Bool) -> String {
        if repsOnly { return "BW" }
        guard let weightTenthsPounds else { return "–" }
        let pounds = Double(weightTenthsPounds) / 10
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
