import Foundation
import SwiftData

struct StudySet: Codable, Equatable {
    var reps: Int?
    var load: Int?
    var target: Int?
    var targetLoad: Int?
    var status: Status
    var logged: Date?
    var rating: RepsInReserve?
}

struct StudySession: Codable, Equatable {
    var date: Date
    var workout: String
    var routine: String
    var block: String?
    var blockWeek: Int?
    var seconds: Double?
    var finished: Bool
    var slot: Int
    var superset: Bool
    var key: String
    var name: String
    var planned: String?
    var primary: Muscle?
    var assisting: [Muscle]?
    var loaded: Bool
    var repsOnly = false
    var targetRIR: Int?
    var sets: [StudySet]
    var warmups: [StudySet] = []
    /// Names the lift was logged under in another app, such as FitNotes' "Hex Bar Dead Lift".
    var importedNames: [String] = []

    var done: [StudySet] { sets.filter { $0.status == .complete } }
    var opening: StudySet? { sets.first.flatMap { $0.status == .complete ? $0 : nil } }
    var best: ProgramExerciseHistory.MaxEstimate? {
        guard loaded else { return nil }
        return .best(
            in: done.compactMap { ProgramExerciseHistory.estimate(load: $0.load, reps: $0.reps, rating: $0.rating) })
    }
    var perLegLunge: Bool {
        let text = name.lowercased()
        return loaded && text.contains("barbell") && text.contains("reverse") && text.contains("lunge")
            && text.contains("per leg")
    }
}

/// One planned or logged workout, for answers that count workouts or their minutes.
struct StudyWorkout: Codable, Equatable {
    let key: String
    let status: Status
    let began: Date?
    let ended: Date?
    let seconds: Double?
    var date: Date? { began ?? ended }
}

struct StudyHistory {
    var options = StudyOptions()
    private(set) var selectedRange: DateInterval?
    private var exerciseMuscles: [Muscle] = []
    let sessions: [StudySession]
    let workouts: [StudyWorkout]
    let credits: [(date: Date, muscle: Muscle, sets: Double)]
    let today: Date
    let firstDate: Date
    /// Changes whenever the logged sets, the day or the weight unit change, so a search can reuse its results.
    let revision: Int
    /// Each own lift as search reads it, by sync key: the joint actions set in Advanced Data or
    /// copied from the lift it moves like, its equipment and its muscles.
    let ownLifts: [String: ExerciseSearch.Document]
    let calendar: Calendar
    let unit: WeightUnit
    static let legs: [Muscle] = [.quads, .glutes, .hamstrings, .calves]
    static let arms: [Muscle] = [.biceps, .triceps, .forearms]
    static let squat = "catalog:barbell-back-squat"
    static let bench = "catalog:barbell-bench-press"
    static let curl = "catalog:cable-curl"

    init(
        programs: [Program], archive: [ArchivedRow], logs: [WorkoutLog], imported: [ImportedSet] = [],
        exercises: [Exercise] = [], unit: WeightUnit, today: Date = .now, calendar: Calendar = .current
    ) {
        let parts = HistoryParts(programs: programs, archive: archive, logs: logs, imported: imported,
                                 exercises: exercises, calendar: calendar)
        self.init(parts: parts, unit: unit, today: today, calendar: calendar)
    }

    /// The history as of `today`, from pieces built for any day.
    init(parts: HistoryParts, unit: WeightUnit, today: Date = .now, calendar: Calendar = .current) {
        self.unit = unit
        self.today = today
        self.calendar = calendar
        ownLifts = parts.ownLifts
        var sessions: [StudySession] = []
        var workouts: [String: StudyWorkout] = [:]
        for part in parts.workouts.values {
            if let date = part.workout.date, date > today { continue }
            workouts[part.workout.key] = part.workout
            sessions += part.sessions.filter { $0.date <= today }
        }
        for part in parts.archived {
            if let date = part.workout.date, date > today { continue }
            workouts[part.workout.key] = part.workout
            if let session = part.session, session.date <= today { sessions.append(session) }
        }
        let importedSessions = parts.imported.filter { $0.date <= today }
        sessions += importedSessions
        for session in importedSessions where workouts[session.workout] == nil {
            workouts[session.workout] = StudyWorkout(
                key: session.workout, status: .complete, began: nil, ended: session.date, seconds: nil)
        }
        self.workouts = workouts.values.sorted { ($0.date ?? .distantFuture, $0.key) < ($1.date ?? .distantFuture, $1.key) }
        self.sessions = sessions.sorted { ($0.date, $0.workout, $0.slot) < ($1.date, $1.workout, $1.slot) }
        let recordedLogs = parts.logs.filter { $0.date <= today }
        self.firstDate = min(self.sessions.first?.date ?? today, recordedLogs.map(\.date).min() ?? today)
        self.credits = recordedLogs.flatMap { log in
            zip(Muscle.allCases, log.sets).map { muscle, sets in (log.date, muscle, sets) }
        } + importedSessions.flatMap(Self.credits)
        var hasher = Hasher()
        hasher.combine(calendar.startOfDay(for: today))
        hasher.combine(unit)
        for session in self.sessions {
            hasher.combine(session.date)
            hasher.combine(session.key)
            for set in session.sets + session.warmups {
                hasher.combine(set.reps)
                hasher.combine(set.load)
                hasher.combine(set.status)
                hasher.combine(set.rating)
            }
        }
        for workout in self.workouts {
            hasher.combine(workout.key)
            hasher.combine(workout.status)
            hasher.combine(workout.seconds)
        }
        for credit in credits {
            hasher.combine(credit.date)
            hasher.combine(credit.sets)
        }
        self.revision = hasher.finalize()
    }

    /// Same credit as a finished workout's log: 1 per set for the primary muscle, 0.5 for each secondary.
    private static func credits(_ session: StudySession) -> [(date: Date, muscle: Muscle, sets: Double)] {
        guard let primary = session.primary else { return [] }
        let sets = Double(session.done.count)
        let assisting = (session.assisting ?? []).filter { $0 != primary }
        return [(session.date, primary, sets)] + assisting.map { (session.date, $0, sets / 2) }
    }

    func configured(for options: StudyOptions) -> Self {
        var history = self
        history.options = options
        history.exerciseMuscles = []
        if !options.exerciseKeys.isEmpty {
            let keys = Set(options.exerciseKeys)
            let represented = Set(sessions.filter { keys.contains($0.key) }.compactMap(\.primary))
            history.exerciseMuscles = Muscle.allCases.filter(represented.contains)
        }
        history.selectedRange = options.period.interval(in: calendar, today: today)
        return history
    }

    var originalPeriod: Bool {
        if case .original = options.period { return true }
        return false
    }
    var asOf: Date { min(today, selectedRange?.end.addingTimeInterval(-1) ?? today) }
    var rangeLabel: String {
        switch options.period {
        case .original: return ""
        case .all: return "All recorded history"
        case .year(let year): return String(year)
        case .day: return selectedRange?.start.formatted(.dateTime.month(.wide).day().year()) ?? ""
        case .month: return selectedRange?.start.formatted(.dateTime.month(.wide).year()) ?? ""
        case .range, .recent: return options.period.label
        }
    }
    func parameter(_ key: StudyParameter, _ fallback: Int) -> Int {
        min(key.range.upperBound, max(key.range.lowerBound, options.parameters[key] ?? fallback))
    }
    func includes(_ date: Date) -> Bool {
        guard let selectedRange else { return true }
        return date >= selectedRange.start && date < selectedRange.end
    }
    /// Historical baselines may cross the lower bound but still end at the exact calendar boundary.
    func throughRangeEnd(_ date: Date) -> Bool {
        date <= today && (selectedRange.map { date < $0.end } ?? true)
    }
    func exerciseMatches(_ session: StudySession) -> Bool {
        options.exerciseKeys.isEmpty || options.exerciseKeys.contains(session.key)
    }
    func muscles(_ fallback: [Muscle]) -> [Muscle] {
        if !options.muscles.isEmpty { return options.muscles }
        return exerciseMuscles.isEmpty ? fallback : exerciseMuscles
    }
    func muscleLabel(_ fallback: [Muscle], _ original: String) -> String {
        guard !options.muscles.isEmpty || !options.exerciseKeys.isEmpty else { return original }
        return muscles(fallback).map { $0.rawValue.capitalized }.joined(separator: ", ")
    }
    func focusKey(_ fallback: String) -> String { options.exerciseKeys.first ?? fallback }
    func exerciseName(for key: String) -> String {
        sessions.first { $0.key == key }?.name
            ?? key.replacingOccurrences(of: "catalog:", with: "").replacingOccurrences(of: "-", with: " ").capitalized
    }
    func focusName(_ fallback: String, _ original: String) -> String {
        options.exerciseKeys.first.map { exerciseName(for: $0) } ?? original
    }
    func lift(_ key: String) -> [StudySession] { sessions.filter { $0.key == key && !$0.done.isEmpty } }
    func focusedLift(_ fallback: String, includeEarlier: Bool = false) -> [StudySession] {
        lift(focusKey(fallback)).filter { includeEarlier ? throughRangeEnd($0.date) : includes($0.date) }
    }
    func weight(_ tenths: Int) -> Double { unit.value(fromTenthsPounds: tenths) }
    func loadText(_ tenths: Int) -> String { "\(unit.format(tenthsPounds: tenths)) \(unit.symbol)" }
    func day(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)) }
    func week(_ date: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: date)!.start }
    func offset(_ date: Date, days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: date)! }
    func days(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
    /// The selected dates trimmed to the logged history, so an axis never runs past today or before the first log.
    /// Nil for a chart's own default dates.
    var chartRange: DateInterval? {
        guard let selectedRange else {
            if case .all = options.period { return DateInterval(start: calendar.startOfDay(for: firstDate), end: endOfToday) }
            return nil
        }
        let start = max(selectedRange.start, calendar.startOfDay(for: firstDate))
        let end = min(selectedRange.end, endOfToday)
        return start < end ? DateInterval(start: start, end: end) : selectedRange
    }
    var endOfToday: Date { offset(calendar.startOfDay(for: today), days: 1) }

    /// Weeks for the weekly charts: the last few by default, otherwise the chosen range cut into
    /// calendar weeks, or months and quarters over long spans.
    func weeklyTimeline(series: Int = 1) -> StudyTimeline {
        let end = offset(calendar.startOfDay(for: asOf), days: 1)
        let range: DateInterval
        if originalPeriod || chartRange == nil {
            let first = offset(week(asOf), days: -(parameter(.weeks, 6) - 1) * 7)
            range = DateInterval(start: first, end: end)
        } else {
            range = chartRange!
        }
        let unit = originalPeriod ? .weekOfYear : StudyTimeline.unit(forWeekly: range, series: series)
        return StudyTimeline(range: range, unit: unit, calendar: calendar)
    }
    var yearStart: Date {
        selectedRange?.start
            ?? (originalPeriod
                ? calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))! : calendar.startOfDay(for: firstDate))
    }
    var yearEnd: Date {
        selectedRange?.end
            ?? (originalPeriod
                ? calendar.date(byAdding: .year, value: 1, to: yearStart)!
                : offset(calendar.startOfDay(for: today), days: 1))
    }
    var annualLabel: String { originalPeriod ? "2026" : rangeLabel }
    func inYear(_ date: Date) -> Bool { date >= yearStart && date < yearEnd }
    func recent(_ date: Date) -> Bool { originalPeriod ? days(date, today) < 28 : includes(date) }
    var recentLabel: String { originalPeriod ? "last 28 days" : rangeLabel }
    var weeksLabel: String { originalPeriod ? "last \(parameter(.weeks, 6)) weeks" : rangeLabel }

    /// Compare equally long observed intervals, including a partial current month or year only up to today.
    var comparisonWindows: (previous: DateInterval, current: DateInterval) {
        let until = offset(calendar.startOfDay(for: asOf), days: 1)
        let length: Int
        if originalPeriod {
            length = parameter(.comparisonDays, 28)
        } else if let selectedRange {
            length = max(1, days(selectedRange.start, until))
        } else {
            length = max(1, days(calendar.startOfDay(for: firstDate), until) / 2)
        }
        let start = selectedRange?.start ?? offset(until, days: -length)
        let upper = max(start, until)
        return (DateInterval(start: offset(start, days: -length), end: start), DateInterval(start: start, end: upper))
    }

    func isLeg(_ session: StudySession) -> Bool {
        let groups = muscles(Self.legs)
        return exerciseMatches(session)
            && (session.primary.map(groups.contains) == true || (session.assisting ?? []).contains(where: groups.contains))
    }

    static func quantile(_ values: [Double], _ p: Double = 0.5) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Double(sorted.count - 1) * p
        let lower = Int(index)
        return sorted[lower] + (sorted[Int(ceil(index))] - sorted[lower]) * (index - Double(lower))
    }
}

extension StudyHistory {
    private static var kept: (stamp: [AnyHashable], history: StudyHistory)?

    /// The history last built for the Data tab, if any.
    static var latest: StudyHistory? { kept?.history }

    /// All saved history. Only what changed since the last call is rebuilt, and nothing at all
    /// when the store, the weight unit and the day are the same.
    static func current(in context: ModelContext, unit: WeightUnit, now: Date = .now,
                        calendar: Calendar = .current) -> StudyHistory {
        let summary = HistorySummary.shared
        let parts = summary.parts(in: context, calendar: calendar)
        let stamp: [AnyHashable] = [summary.revision, unit, calendar.startOfDay(for: now)]
        if let kept, kept.stamp == stamp { return kept.history }
        let history = StudyHistory(parts: parts, unit: unit, today: now, calendar: calendar)
        kept = (stamp, history)
        return history
    }

    /// Forgets the kept history, as when the local cache is cleared.
    static func forget() { kept = nil }

    /// Everything the Data tab reads, fetched from the store.
    init(context: ModelContext, unit: WeightUnit, today: Date = .now, calendar: Calendar = .current) {
        self.init(parts: HistoryParts(context: context, calendar: calendar), unit: unit, today: today, calendar: calendar)
    }
}
