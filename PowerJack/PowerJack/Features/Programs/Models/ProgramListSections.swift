//
//  ProgramListSections.swift
//  PowerJack
//

import Foundation

/// Splits programs into the ones still to run and past ones grouped by the year they started.
struct ProgramListSections<Item> {
    struct Year {
        /// Nil for past programs that never started a workout.
        let year: Int?
        let items: [Item]

        /// This year and last year start open; older years and "No workouts" start closed.
        func startsExpanded(now: Date = .now, calendar: Calendar = .current) -> Bool {
            guard let year else { return false }
            return year >= calendar.component(.year, from: now) - 1
        }
    }

    /// The active program first, then programs not started yet.
    let current: [Item]
    /// Newest year first. Within a year, newest start first.
    let past: [Year]

    init(
        _ items: [Item],
        status: (Item) -> Status,
        startedAt: (Item) -> Date?,
        calendar: Calendar = .current
    ) {
        current = items.filter { status($0) == .active } + items.filter { status($0) == .planned }

        let finished = items
            .filter { status($0).isFinished }
            .map { (item: $0, start: startedAt($0)) }
            .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
        let byYear = Dictionary(grouping: finished) { $0.start.map { calendar.component(.year, from: $0) } }
        past = byYear
            .sorted { ($0.key ?? .min) > ($1.key ?? .min) }
            .map { Year(year: $0.key, items: $0.value.map(\.item)) }
    }
}

enum ProgramDateRange {
    /// e.g. "Mar 3 – May 12", or "Dec 1, 2025 – Feb 9, 2026" when it crosses a year.
    static func text(
        from start: Date,
        to end: Date?,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let end = end.map { max($0, start) } ?? start
        let crossesYear = calendar.component(.year, from: start) != calendar.component(.year, from: end)

        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated)
            .day()
        if crossesYear { style = style.year() }

        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(style)
        }
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}
