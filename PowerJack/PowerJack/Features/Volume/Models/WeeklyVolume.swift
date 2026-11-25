//
//  WeeklyVolume.swift
//  PowerJack
//
//  Average working sets per week for each muscle, over a chosen range of the training history.
//

import Foundation

enum VolumeRange: CaseIterable, Identifiable, Hashable {
    case currentProgram
    case days30
    case days90
    case yearToDate
    case year

    var id: Self { self }

    var name: String {
        switch self {
        case .currentProgram: "Current Program"
        case .days30: "30 days"
        case .days90: "90 days"
        case .yearToDate: "Year to date"
        case .year: "1 year"
        }
    }

    /// The range's first day, when the range is calendar-based.
    func start(before now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .currentProgram: nil
        case .days30: calendar.date(byAdding: .day, value: -30, to: now)
        case .days90: calendar.date(byAdding: .day, value: -90, to: now)
        case .yearToDate: calendar.dateInterval(of: .year, for: now)?.start
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        }
    }
}

enum WorkoutDateFilter: Hashable {
    case day(Int, month: Int, year: Int?)
    case month(Int, year: Int?)
    case year(Int)

    var name: String {
        let parts = components
        guard let month = parts.month else { return parts.year.map(String.init) ?? "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        let monthName = calendar.standaloneMonthSymbols[month - 1]
        if let day = parts.day {
            let date = "\(monthName) \(day)"
            return parts.year.map { "\(date), \($0)" } ?? date
        }
        return parts.year.map { "\(monthName) \($0)" } ?? monthName
    }

    func includes(_ date: Date, calendar: Calendar) -> Bool {
        let filter = components
        let date = gregorian(in: calendar).dateComponents([.year, .month, .day], from: date)
        return (filter.year == nil || filter.year == date.year)
            && (filter.month == nil || filter.month == date.month)
            && (filter.day == nil || filter.day == date.day)
    }

    private var components: DateComponents {
        switch self {
        case .day(let day, let month, let year):
            return DateComponents(year: year, month: month, day: day)
        case .month(let month, let year):
            return DateComponents(year: year, month: month)
        case .year(let year):
            return DateComponents(year: year)
        }
    }

    /// Calendar periods that overlap the log history. A month or day without a year repeats each year.
    func periods(from firstDate: Date, through now: Date, calendar: Calendar) -> [DateInterval] {
        guard firstDate <= now else { return [] }
        let calendar = gregorian(in: calendar)
        let parts = components
        let unit: Calendar.Component
        switch self {
        case .day: unit = .day
        case .month: unit = .month
        case .year: unit = .year
        }
        let years = parts.year.map { $0...$0 } ?? calendar.component(.year, from: firstDate)...calendar.component(.year, from: now)
        return years.compactMap { year in
            let start = DateComponents(year: year, month: parts.month ?? 1, day: parts.day ?? 1)
            guard start.isValidDate(in: calendar), let date = calendar.date(from: start),
                  let period = calendar.dateInterval(of: unit, for: date),
                  period.end > firstDate, period.start <= now else { return nil }
            return period
        }
    }

    private func gregorian(in calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }
}

enum WeeklyVolume {
    private static let secondsPerWeek: TimeInterval = 7 * 24 * 60 * 60

    struct TrendPoint: Identifiable {
        let week: Date
        let setsByMuscle: [Muscle: Double]
        let periodStart: Date?
        var id: Date { week }
    }

    static func logs(_ logs: [WorkoutLog], matching types: Set<TemplateType>, programs: [Program]) -> [WorkoutLog] {
        guard !types.isEmpty else { return logs }

        var sessionTypes: [UUID: TemplateType] = [:]
        var datedTypes: [(date: Date, type: TemplateType)] = []
        for program in programs {
            for workout in program.programWeeks.flatMap(\.workouts) {
                if let id = workout.syncID { sessionTypes[id] = program.templateType }
                if let date = workout.endedAt { datedTypes.append((date, program.templateType)) }
            }
        }
        return logs.filter { log in
            if let type = log.programType { return types.contains(type) }
            if let id = log.sessionID { return sessionTypes[id].map(types.contains) ?? false }
            let candidates = Set(datedTypes.lazy.filter { abs($0.date.timeIntervalSince(log.date)) <= 1 }.map(\.type))
            return !candidates.isEmpty && candidates.isSubset(of: types)
        }
    }

    static func trend(
        of logs: [WorkoutLog], in range: VolumeRange, currentProgram: Program? = nil,
        dateFilter: WorkoutDateFilter? = nil, selectedMuscles: Set<Muscle> = [],
        now: Date = .now, calendar: Calendar = .current
    ) -> [TrendPoint] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let scoped = dateFilter == nil && range == .currentProgram ? programLogs(logs, for: currentProgram) : logs
        let start = (dateFilter == nil ? range.start(before: now, calendar: calendar) : nil) ?? .distantPast
        let muscles = Muscle.allCases.filter { selectedMuscles.isEmpty || selectedMuscles.contains($0) }
        var totals: [Date: [Muscle: Double]] = [:]
        for log in scoped where log.date >= start && log.date < currentWeek {
            guard dateFilter?.includes(log.date, calendar: calendar) ?? true,
                  let week = calendar.dateInterval(of: .weekOfYear, for: log.date)?.start,
                  week >= start else { continue }
            for muscle in muscles {
                totals[week, default: [:]][muscle, default: 0] += log.sets(for: muscle)
            }
        }
        guard let firstWeek = totals.keys.min() else { return [] }

        func points(from startWeek: Date, until end: Date, periodStart: Date? = nil) -> [TrendPoint] {
            var week = startWeek
            var points: [TrendPoint] = []
            while week < end {
                points.append(TrendPoint(week: week, setsByMuscle: totals[week] ?? [:], periodStart: periodStart))
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
                week = next
            }
            return points
        }

        guard let dateFilter else { return points(from: firstWeek, until: currentWeek) }
        return dateFilter.periods(from: firstWeek, through: currentWeek, calendar: calendar).flatMap { period -> [TrendPoint] in
            guard let startWeek = calendar.dateInterval(of: .weekOfYear, for: period.start)?.start else { return [] }
            return points(from: max(startWeek, firstWeek), until: min(period.end, currentWeek), periodStart: period.start)
        }
    }

    /// Average sets per week for every muscle, in catalog order.
    ///
    /// The range starts at the first logged workout when that's more recent,
    /// so someone new to the app isn't averaged over weeks they hadn't started yet.
    /// A range never counts as less than a week.
    static func averages(
        of logs: [WorkoutLog],
        in range: VolumeRange,
        currentProgram: Program? = nil,
        dateFilter: WorkoutDateFilter? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Muscle: Double] {
        let logs = dateFilter == nil && range == .currentProgram ? programLogs(logs, for: currentProgram) : logs
        guard let firstLog = logs.map(\.date).min() else { return [:] }

        let start = max(firstLog, (dateFilter == nil ? range.start(before: now, calendar: calendar) : nil) ?? firstLog)
        let logsInRange = logs.filter {
            $0.date >= start && $0.date <= now && (dateFilter?.includes($0.date, calendar: calendar) ?? true)
        }
        if dateFilter != nil && logsInRange.isEmpty { return [:] }
        let weeksInRange = dateFilter.map { filter in
            let periods = filter.periods(from: start, through: now, calendar: calendar)
            if case .day = filter { return Double(periods.count) }
            let seconds = periods.reduce(0.0) { total, period in
                total + min(period.end, now).timeIntervalSince(max(period.start, start))
            }
            return seconds / secondsPerWeek
        } ?? (now.timeIntervalSince(start) / secondsPerWeek)
        let weeks = max(1, weeksInRange)

        var averages: [Muscle: Double] = [:]
        for muscle in Muscle.allCases {
            let total = logsInRange.reduce(0) { $0 + $1.sets(for: muscle) }
            averages[muscle] = total / weeks
        }
        return averages
    }

    private static func programLogs(_ logs: [WorkoutLog], for program: Program?) -> [WorkoutLog] {
        guard let program else { return [] }
        let workouts = program.programWeeks.flatMap(\.workouts)
        let sessionIDs = Set(workouts.compactMap(\.syncID))
        let endDates = workouts.compactMap(\.endedAt)
        return logs.filter { log in
            if let id = log.sessionID { return sessionIDs.contains(id) }
            // Logs from before session IDs were written as the workout ended.
            return endDates.contains { abs($0.timeIntervalSince(log.date)) <= 1 }
        }
    }
}
