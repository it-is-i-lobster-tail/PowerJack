//
//  RestCallout.swift
//  PowerJack
//
//  What the voice says when a rest ends: only what to do next, in as few words as it takes.
//

import Foundation

nonisolated struct RestCallout: Hashable {
    /// How long after its rest ends a callout can still be said, like the haptic cues.
    static let lateLimit: TimeInterval = 2

    /// When the rest ends and the callout is spoken.
    var endsAt: Date
    var phrase: RestPhrase

    /// Too long after the rest ended to say, as when iOS kept PowerJack suspended past it.
    func isLate(at date: Date) -> Bool {
        date.timeIntervalSince(endsAt) > Self.lateLimit
    }
}

/// Words the voice says, and the recorded clips that say them, in order.
nonisolated struct RestPhrase: Hashable {
    /// e.g. "Start set. 225 pounds, 10 reps."
    var text: String
    /// e.g. ["start-set", "lb-225", "reps-10"]. See `RestVoiceClips`.
    var clips: [String]

    static let superset = RestPhrase(text: "Start superset.", clips: ["start-superset"])

    /// e.g. "Start set. 225 pounds, 10 reps." The weight is left out when it hasn't changed.
    static func set(weightTenthsPounds: Int?, reps: Int?, unit: WeightUnit) -> RestPhrase {
        var load: [(text: String, clip: String)] = []
        if let weightTenthsPounds {
            let number = spokenNumber(tenthsPounds: weightTenthsPounds, unit: unit)
            let name = switch unit {
            case .pounds: number == "1" ? "pound" : "pounds"
            case .kilograms: number == "1" ? "kilo" : "kilos"
            }
            load.append(("\(number) \(name)", "\(unit == .kilograms ? "kg" : "lb")-\(number)"))
        }
        if let reps {
            load.append((reps == 1 ? "1 rep" : "\(reps) reps", "reps-\(reps)"))
        }

        let words = load.map(\.text).joined(separator: ", ")
        return RestPhrase(
            text: words.isEmpty ? "Start set." : "Start set. \(words).",
            clips: ["start-set"] + load.map(\.clip)
        )
    }

    /// What the voice sounds like, for Settings.
    static func sample(in unit: WeightUnit) -> RestPhrase {
        set(weightTenthsPounds: unit == .kilograms ? 2205 : 2250, reps: 10, unit: unit)
    }

    /// e.g. "225" or "102.5", as the screen shows it. Always written the English way, since the voice is English.
    private static func spokenNumber(tenthsPounds: Int, unit: WeightUnit) -> String {
        let pounds = Double(tenthsPounds) / 10
        let weight = unit == .kilograms ? pounds * WeightUnit.kilogramsPerPound : pounds
        return weight.formatted(
            .number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}

extension Workout {
    /// The callout for the rest running now. A superset only says to start the next round;
    /// otherwise the weight is said when it differs from the last one logged on the exercise.
    var restCallout: RestCallout? {
        guard let rest = currentRest, let current = currentSet else { return nil }
        guard group(of: current.workoutExercise).count == 1 else {
            return RestCallout(endsAt: rest.endsAt, phrase: .superset)
        }

        let lastWeight = current.workoutExercise.workoutSets
            .last { $0.status == .complete && $0.weightTenthsPounds != nil }?
            .weightTenthsPounds
        let newWeight = rest.weightTenthsPounds.flatMap { $0 == lastWeight ? nil : $0 }
        return RestCallout(
            endsAt: rest.endsAt,
            phrase: .set(weightTenthsPounds: newWeight, reps: rest.reps, unit: WeightUnit.current)
        )
    }
}
