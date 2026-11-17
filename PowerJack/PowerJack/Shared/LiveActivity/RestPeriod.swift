//
//  RestPeriod.swift
//  PowerJack
//
//  The rest between two sets and the set that comes next.
//  Compiled into the widget extension too, where it is the Live Activity's content state.
//

import Foundation

nonisolated struct RestPeriod: Codable, Hashable {
    /// When the set that started this rest was completed.
    var startedAt: Date
    var endsAt: Date
    var exerciseName: String
    /// 1-based position of the next set among its exercise's warmups or working sets.
    var setNumber: Int
    /// How many warmups or working sets the exercise has, whichever the next set is.
    var setCount: Int
    var isWarmup = false
    /// `nil` means the set is open ended: the lifter stops with `repsLeft` reps left.
    var reps: Int?
    /// The exercise's reps-left target, shown when the set has no reps to aim for.
    var repsLeft: Int?
    /// `nil` for bodyweight sets or when no weight is known yet.
    var weightTenthsPounds: Int?
    /// Shows the weight in kilograms. Weights are always stored in tenths of a pound.
    var usesKilograms: Bool?

    /// How long "Start set" stays up after the rest runs out.
    static let readyWindow: TimeInterval = 10 * 60

    var interval: ClosedRange<Date> { startedAt...max(startedAt, endsAt) }
    var duration: TimeInterval { endsAt.timeIntervalSince(startedAt) }
    var expiresAt: Date { endsAt.addingTimeInterval(Self.readyWindow) }

    func isResting(at date: Date) -> Bool { date < endsAt }
    func isExpired(at date: Date) -> Bool { date >= expiresAt }

    func remaining(at date: Date) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(date))
    }

    /// 1 when the rest starts, 0 when it is over.
    func fractionRemaining(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, remaining(at: date) / duration)
    }

    // MARK: Display

    var setText: String {
        WorkoutActivityState.setText(number: setNumber, count: setCount, isWarmup: isWarmup)
    }

    /// e.g. "8 reps × 225 lb", "3 reps left × 135 lb", "5 reps × 102.5 kg", "8 reps × BW" or "12 reps".
    var prescriptionText: String {
        let repsText = reps.map { $0 == 1 ? "1 rep" : "\($0) reps" }
            ?? repsLeft.map { $0 == 1 ? "1 rep left" : "\($0) reps left" }
        guard let weightTenthsPounds else { return repsText ?? "" }
        let weight = ActivitySet.weight(tenthsPounds: weightTenthsPounds, inKilograms: usesKilograms == true)
        let load = weightTenthsPounds == 0 ? weight : "\(weight) \(usesKilograms == true ? "kg" : "lb")"
        return repsText.map { "\($0) × \(load)" } ?? load
    }

    var detailText: String {
        prescriptionText.isEmpty ? setText : "\(setText) · \(prescriptionText)"
    }
}
