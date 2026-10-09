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
    /// `nil` means the set is open ended (2 reps in reserve).
    var reps: Int?
    /// `nil` for bodyweight sets or when no weight is known yet.
    var weightTenthsPounds: Int?

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

    /// e.g. "8 reps × 225 lb", "2 RIR × 135 lb", or "12 reps".
    var prescriptionText: String {
        let repsText = reps.map { $0 == 1 ? "1 rep" : "\($0) reps" } ?? "2 RIR"
        guard let weightTenthsPounds else { return repsText }
        let pounds = (Double(weightTenthsPounds) / 10).formatted(.number.precision(.fractionLength(0...1)))
        return "\(repsText) × \(pounds) lb"
    }

    var detailText: String { "\(setText) · \(prescriptionText)" }
}
