//
//  HintOccasion.swift
//  PowerJack
//
//  The workouts that show a hint, so hints arrive as the lifter gets to them.
//

import Foundation

/// The early workouts of the lifter's first program. Once the lifter moves past
/// week 3, day 1, no workout is an occasion again, so later programs stay quiet.
nonisolated enum HintOccasion: String {
    case weekOneDayOne
    case weekOneDayTwo
    case weekTwoDayOne
    case weekTwoDayTwo
    case weekThreeDayOne

    private static let finishedKey = "hints.workoutOccasionsFinished"

    @MainActor
    init?(weekNumber: Int?, workout: Workout) {
        guard !UserDefaults.standard.bool(forKey: Self.finishedKey) else { return nil }

        switch (weekNumber, workout.order) {
        case (1, 0): self = .weekOneDayOne
        case (1, 1): self = .weekOneDayTwo
        case (2, 0): self = .weekTwoDayOne
        case (2, 1): self = .weekTwoDayTwo
        case (3, 0): self = .weekThreeDayOne
        default: return nil
        }
    }

    /// The workouts that repeat how logging sets and resting work, so it sinks in.
    var showsWorkoutBasics: Bool { [.weekOneDayOne, .weekOneDayTwo, .weekTwoDayOne].contains(self) }

    /// Starting a workout after week 3, day 1 ends the occasions for good.
    @MainActor
    static func workoutStarted(weekNumber: Int?, workout: Workout) {
        guard let weekNumber, weekNumber > 3 || (weekNumber == 3 && workout.order > 0) else { return }
        UserDefaults.standard.set(true, forKey: finishedKey)
    }
}
