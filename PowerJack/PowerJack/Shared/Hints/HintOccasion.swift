//
//  HintOccasion.swift
//  PowerJack
//
//  The workouts that repeat a hint, so it gets seen more than once.
//

import Foundation

/// Days 1 and 2 of week 1, then day 1 of week 2. Once the lifter moves past that,
/// no workout is an occasion again, so later programs stay quiet.
nonisolated enum HintOccasion: String {
    case weekOneDayOne
    case weekOneDayTwo
    case weekTwoDayOne

    private static let finishedKey = "hints.workoutOccasionsFinished"

    @MainActor
    init?(weekNumber: Int?, workout: Workout) {
        guard !UserDefaults.standard.bool(forKey: Self.finishedKey) else { return nil }

        switch (weekNumber, workout.order) {
        case (1, 0): self = .weekOneDayOne
        case (1, 1): self = .weekOneDayTwo
        case (2, 0): self = .weekTwoDayOne
        default: return nil
        }
    }

    var isWeekOne: Bool { self != .weekTwoDayOne }

    /// Starting any later workout ends the occasions for good.
    @MainActor
    static func workoutStarted(weekNumber: Int?, workout: Workout) {
        guard let weekNumber, weekNumber >= 2,
              HintOccasion(weekNumber: weekNumber, workout: workout) == nil
        else {
            return
        }
        UserDefaults.standard.set(true, forKey: finishedKey)
    }
}
