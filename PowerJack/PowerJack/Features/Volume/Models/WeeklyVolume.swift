//
//  WeeklyVolume.swift
//  PowerJack
//
//  Average working sets per week for each muscle, over a chosen range of the training history.
//

import Foundation

enum VolumeRange: CaseIterable, Identifiable, Hashable {
    case days30
    case days90
    case year
    case all

    var id: Self { self }

    var name: String {
        switch self {
        case .days30: "30 Days"
        case .days90: "90 Days"
        case .year: "1 Year"
        case .all: "All"
        }
    }

    /// The range's first day, or `nil` for all of history.
    func start(before now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .days30: calendar.date(byAdding: .day, value: -30, to: now)
        case .days90: calendar.date(byAdding: .day, value: -90, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }
}

enum WeeklyVolume {
    private static let secondsPerWeek: TimeInterval = 7 * 24 * 60 * 60

    /// Average sets per week for every muscle, in catalog order.
    ///
    /// The range starts at the first logged workout when that's more recent,
    /// so someone new to the app isn't averaged over weeks they hadn't started yet.
    /// A range never counts as less than a week.
    static func averages(
        of logs: [WorkoutLog],
        in range: VolumeRange,
        now: Date = .now
    ) -> [Muscle: Double] {
        guard let firstLog = logs.map(\.date).min() else { return [:] }

        let start = max(firstLog, range.start(before: now) ?? firstLog)
        let weeks = max(1, now.timeIntervalSince(start) / secondsPerWeek)
        let logsInRange = logs.filter { $0.date >= start && $0.date <= now }

        var averages: [Muscle: Double] = [:]
        for muscle in Muscle.allCases {
            let total = logsInRange.reduce(0) { $0 + $1.sets(for: muscle) }
            averages[muscle] = total / weeks
        }
        return averages
    }
}
