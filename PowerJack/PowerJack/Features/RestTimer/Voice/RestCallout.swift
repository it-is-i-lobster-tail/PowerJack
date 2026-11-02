//
//  RestCallout.swift
//  PowerJack
//
//  What the voice says when a rest ends: only what to do next, in as few words as it takes.
//

import Foundation

nonisolated struct RestCallout: Hashable {
    /// When the rest ends and the callout is spoken.
    var endsAt: Date
    var text: String

    static let superset = "Start superset."

    /// e.g. "Start set. 225 pounds, 10 reps." The weight is left out when it hasn't changed.
    static func text(weightTenthsPounds: Int?, reps: Int?, unit: WeightUnit) -> String {
        let load = [
            weightTenthsPounds.map { spokenWeight(tenthsPounds: $0, unit: unit) },
            reps.map { $0 == 1 ? "1 rep" : "\($0) reps" },
        ]
        .compactMap(\.self)
        .joined(separator: ", ")
        return load.isEmpty ? "Start set." : "Start set. \(load)."
    }

    /// What the voice sounds like, for Settings.
    static func sample(in unit: WeightUnit) -> String {
        text(weightTenthsPounds: unit == .kilograms ? 2205 : 2250, reps: 10, unit: unit)
    }

    /// e.g. "225 pounds" or "102.5 kilos". Always written the English way, since the voice is English.
    private static func spokenWeight(tenthsPounds: Int, unit: WeightUnit) -> String {
        let pounds = Double(tenthsPounds) / 10
        let weight = unit == .kilograms ? pounds * WeightUnit.kilogramsPerPound : pounds
        let number = weight.formatted(
            .number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))
        )
        return "\(number) \(unit == .kilograms ? "kilos" : "pounds")"
    }
}

extension Workout {
    /// The callout for the rest running now. A superset only says to start the next round;
    /// otherwise the weight is said when it differs from the last one logged on the exercise.
    var restCallout: RestCallout? {
        guard let rest = currentRest, let current = currentSet else { return nil }
        guard group(of: current.workoutExercise).count == 1 else {
            return RestCallout(endsAt: rest.endsAt, text: RestCallout.superset)
        }

        let lastWeight = current.workoutExercise.workoutSets
            .last { $0.status == .complete && $0.weightTenthsPounds != nil }?
            .weightTenthsPounds
        let newWeight = rest.weightTenthsPounds.flatMap { $0 == lastWeight ? nil : $0 }
        return RestCallout(
            endsAt: rest.endsAt,
            text: RestCallout.text(weightTenthsPounds: newWeight, reps: rest.reps, unit: WeightUnit.current)
        )
    }
}
